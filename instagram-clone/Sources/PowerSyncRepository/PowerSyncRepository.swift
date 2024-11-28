@preconcurrency import AnyCodable
import Dependencies
import Env
import Foundation
import LoggerDependency
import PowerSync
import Supabase
import OSLog

extension Logger {
	static let supabase = Self(subsystem: "com.lamberthyl.instagram-clone", category: "supabase")
}

struct SupaLogger: SupabaseLogger {
	func log(message: SupabaseLogMessage) {
		let logger = Logger.supabase

		switch message.level {
		case .debug: logger.debug("\(message, privacy: .public)")
		case .error: logger.error("\(message, privacy: .public)")
		case .verbose: logger.info("\(message, privacy: .public)")
		case .warning: logger.notice("\(message, privacy: .public)")
		}
	}
}

let encoder: JSONEncoder = {
	let encoder = PostgrestClient.Configuration.jsonEncoder
	encoder.keyEncodingStrategy = .convertToSnakeCase
	return encoder
}()

let decoder: JSONDecoder = {
	let decoder = PostgrestClient.Configuration.jsonDecoder
	decoder.keyDecodingStrategy = .convertFromSnakeCase
	return decoder
}()

final class SupabaseConnector: PowerSyncBackendConnector {
	public let db: PowerSyncDatabase
	public let env: any Env
	public let client: SupabaseClient
	public init(db: PowerSyncDatabase, env: any Env, supabaseURL: URL) {
		self.db = db
		self.env = env
		self.client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: env.supabaseAnonKey)
	}

	@Dependency(\.logger[subsystem: "SupabaseConnector", category: "PowerSyncRepository"]) var logger

	override public func fetchCredentials() async throws -> PowerSyncCredentials? {
		guard let session = client.auth.currentSession else {
			throw AuthError.sessionMissing
		}
		logger.debug("\(String(describing: session.user))")
		let token = session.accessToken
		let userId = session.user.id.uuidString
		return PowerSyncCredentials(
			endpoint: env.powerSyncUrl,
			token: token,
			userId: userId
		)
	}

	override public func uploadData(database: any PowerSyncDatabase) async throws {
		guard let transaction = try await database.getNextCrudTransaction() else {
			return
		}
		do {
			for entry in transaction.crud {
				let tableName = entry.table

				let table = client.from(tableName)

				switch entry.op {
				case .put:
					var data: [String: AnyCodable] = entry.opData?.mapValues { AnyCodable($0) } ?? [:]
					data["id"] = AnyCodable(entry.id)
					try await table.upsert(data).execute()
				case .patch:
					guard let opData = entry.opData else { continue }
					let encodableData = opData.mapValues { AnyCodable($0) }
					try await table.update(encodableData).eq("id", value: entry.id).execute()
				case .delete:
					try await table.delete().eq("id", value: entry.id).execute()
				}
			}

			try await transaction.complete.invoke(p1: nil)

		} catch {
			throw error
		}
	}

	fileprivate func safePrefetchCredentials() async throws {
		_ = try await prefetchCredentials()
	}
}

public actor PowerSyncRepository {
	private let env: any Env
	private let supabseURL: URL
	private let factory = DatabaseDriverFactory()
	public let supabase: SupabaseClient
	public let db: UncheckedSendable<PowerSyncDatabase>
	private var connector: UncheckedSendable<SupabaseConnector?>
	public init?(env: any Env) {
		guard let supabaseURL = URL(string: env.supabaseUrl) else {
			return nil
		}
		self.supabseURL = supabaseURL
		self.env = env
		self.db = UncheckedSendable(PowerSyncDatabase(factory: factory, schema: .appSchema, dbFilename: "instagram-clone.sqlite"))
		self.supabase = SupabaseClient(
			supabaseURL: supabaseURL,
			supabaseKey: env.supabaseAnonKey,
			options: SupabaseClientOptions(
				db: .init(encoder: encoder, decoder: decoder),
				auth: SupabaseClientOptions.AuthOptions(flowType: .implicit),
				global: .init(logger: SupaLogger())
			)
		)
		connector = UncheckedSendable(nil)
	}
	public static func instanceWithInitilized(env: any Env) -> PowerSyncRepository {
		guard let powerSyncRepository = PowerSyncRepository(env: env) else {
			fatalError("")
		}
		Task {
			await powerSyncRepository.initialize()
		}
		return powerSyncRepository
	}

	public var authState: AsyncStream<(
		event: AuthChangeEvent,
		session: Session?
	)> {
		supabase.auth.authStateChanges
	}

	private var initialized = false
	public var isLoggedIn: Bool {
		supabase.auth.currentSession?.accessToken != nil
	}

	public func initialize(offlineMode: Bool = false) async {
		if !initialized {
			await openDatabase()
			initialized = true
		}
	}

	@Dependency(\.logger[subsystem: "PowerSync", category: "PowerSyncRepository"]) var logger
	private func openDatabase() async {
		if isLoggedIn {
			connector = UncheckedSendable(SupabaseConnector(db: db.wrappedValue, env: env, supabaseURL: supabseURL))
			do {
				try await db.wrappedValue.connect(connector: connector.wrappedValue!, crudThrottleMs: 1000, retryDelayMs: 5000, params: [:])
			} catch {
				logger.error("\(String(describing: error.localizedDescription))")
			}
		}
		do {
			for await (event, _) in supabase.auth.authStateChanges {
				if event == .signedIn || event == .passwordRecovery {
					connector = UncheckedSendable(SupabaseConnector(db: db.wrappedValue, env: env, supabaseURL: supabseURL))
					try await db.wrappedValue.connect(connector: connector.wrappedValue!, crudThrottleMs: 1000, retryDelayMs: 5000, params: [:])
				} else if event == .signedOut {
					connector.wrappedValue = nil
					try await db.wrappedValue.disconnect()
				} else if event == .tokenRefreshed {
					_ = try await connector.wrappedValue?.safePrefetchCredentials()
				}
			}
		} catch {
			logger.error("\(String(describing: error.localizedDescription))")
		}
	}
	public func updateUser(email: String? = nil, phone: String? = nil, password: String? = nil, nonce: String? = nil, data: [String: AnyJSON]? = nil) async throws {
		try await supabase.auth.update(user: UserAttributes(email: email, phone: phone, password: password, nonce: nonce, data: data))
	}
	public func resetPassword(email: String, redirectTo: String?) async throws {
		try await supabase.auth.resetPasswordForEmail(email, redirectTo: URL(string: redirectTo ?? ""))
	}
	public func verifyOTP(token: String, email: String) async throws {
		try await supabase.auth.verifyOTP(email: email, token: token, type: .recovery)
	}
}
