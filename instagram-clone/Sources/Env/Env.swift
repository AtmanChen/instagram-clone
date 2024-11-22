import Foundation

public protocol Env {
	var supabaseUrl: String { get }
	var supabaseAnonKey: String { get }
	var powerSyncUrl: String { get }
}

public struct Envionment: Env, Sendable {
	public let envName: String
	public let supabaseUrl: String
	public let supabaseAnonKey: String
	public let powerSyncUrl: String
	private init(
		envName: String,
		supabaseUrl: String,
		supabaseAnonKey: String,
		powerSyncUrl: String
	) {
		self.envName = envName
		self.supabaseUrl = supabaseUrl
		self.supabaseAnonKey = supabaseAnonKey
		self.powerSyncUrl = powerSyncUrl
	}

	public static let current: Envionment = {
		let config = loadConfiguration()
		return Envionment(
			envName: config["ENV_NAME"] as! String,
			supabaseUrl: config["SUPABASE_URL"] as! String,
			supabaseAnonKey: config["SUPABASE_ANON_KEY"] as! String,
			powerSyncUrl: config["POWERSYNC_URL"] as! String
		)
	}()

	private static func loadConfiguration() -> [String: Any] {
		let filename: String = {
			if let config = ProcessInfo.processInfo.environment["BUILD_CONFIGURATION"] {
				switch config {
				case "DEBUG": return "env.debug"
				case "STAGING": return "env.staging"
				case "RELEASE": return "env.production"
				default: fatalError("BUILD_CONFIGURATION NOT AVAILABLE!")
				}
			}
			fatalError("BUILD_CONFIGURATION NOT AVAILABLE!")
		}()
		guard let url = Bundle.module.url(forResource: filename, withExtension: "plist"),
		      let config = NSDictionary(contentsOf: url) as? [String: Any]
		else {
			fatalError("Failed to load environment configuration")
		}

		return config
	}
}
