import AppUI
import ComposableArchitecture
import FeedFeature
import Foundation
import ReelsFeature
import Shared
import SwiftUI
import TimelineFeature
import UserClient
import UserProfileFeature

public enum HomeTab: Identifiable, Hashable, CaseIterable {
	case feed
	case timeline
	case reels
	case userProfile

	public var id: String {
		switch self {
		case .feed: return "feed"
		case .timeline: return "timeline"
		case .reels: return "reels"
		case .userProfile: return "userProfile"
		}
	}
}

typealias IconNavBarItemView = NavBarItemView<EmptyView>

extension NavBarItemView {
	static func feed() -> IconNavBarItemView { IconNavBarItemView(icon: .system("house.fill")) }
	static func timeline() -> IconNavBarItemView { IconNavBarItemView(icon: .system("magnifyingglass")) }
	static func reels() -> IconNavBarItemView { IconNavBarItemView(icon: .system("play.rectangle.on.rectangle.fill")) }
}

@Reducer
public struct HomeReducer {
	public init() {}
	@ObservableState
	public struct State: Equatable {
		var authenticatedUser: User
		var currentTab: HomeTab = .userProfile
		var showAppLoadingIndeterminate = false
		var feed = FeedReducer.State()
		var timeline = TimelineReducer.State()
		var reels = ReelsReducer.State()
		var userProfile: UserProfileReducer.State
		public init(authenticatedUser: User) {
			self.authenticatedUser = authenticatedUser
			self.userProfile = UserProfileReducer.State(authenticatedUserId: authenticatedUser.id, profileUserId: authenticatedUser.id)
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		case feed(FeedReducer.Action)
		case timeline(TimelineReducer.Action)
		case task
		case reels(ReelsReducer.Action)
		case authenticatedUserProfileUpdated(User)
		case userProfile(UserProfileReducer.Action)
		case updateAppLoadingIndeterminate(show: Bool)
	}

	@Dependency(\.userClient.databaseClient) var databaseClient

	public var body: some ReducerOf<Self> {
		BindingReducer()
		Scope(state: \.feed, action: \.feed) {
			FeedReducer()
		}
		Scope(state: \.timeline, action: \.timeline) {
			TimelineReducer()
		}
		Scope(state: \.reels, action: \.reels) {
			ReelsReducer()
		}
		Scope(state: \.userProfile, action: \.userProfile) {
			UserProfileReducer()
				._printChanges()
		}
		Reduce { state, action in
			switch action {
			case let .authenticatedUserProfileUpdated(user):
				state.authenticatedUser = user
				return .none
			case .binding:
				return .none
			case .feed:
				return .none
			case .timeline:
				return .none
			case .task:
				return .run { [userId = state.authenticatedUser.id] send in
					for await user in await databaseClient.profile(userId) {
						await send(.authenticatedUserProfileUpdated(user))
					}
				}
			case .reels:
				return .none
			case .userProfile:
				return .none
			case let .updateAppLoadingIndeterminate(show):
				guard state.showAppLoadingIndeterminate != show else {
					return .none
				}
				state.showAppLoadingIndeterminate = show
				return .none
			}
		}
	}
}

public struct HomeView: View {
	@Bindable var store: StoreOf<HomeReducer>
	@Environment(\.textTheme) var textTheme
	@State private var currentTab: HomeTab = .userProfile
	public init(store: StoreOf<HomeReducer>) {
		self.store = store
	}

	public var body: some View {
		NavigationStack {
			TabView(selection: $currentTab) {
				FeedView(store: store.scope(state: \.feed, action: \.feed))
					.tag(HomeTab.feed)
				TimelineView(store: store.scope(state: \.timeline, action: \.timeline))
					.tag(HomeTab.timeline)
				ReelsView(store: store.scope(state: \.reels, action: \.reels))
					.tag(HomeTab.reels)
				UserProfileView(store: store.scope(state: \.userProfile, action: \.userProfile))
					.tag(HomeTab.userProfile)
			}
			.task {
				await store.send(.task).finish()
			}
			.overlayPreferenceValue(CustomTabBarVisiblePreference.self, alignment: .bottom) { isVisible in
				if isVisible != false {
					HStack {
						ForEach(HomeTab.allCases) { tab in
							Button {
								withAnimation {
									currentTab = tab
								}
							} label: {
								switch tab {
								case .feed:
									IconNavBarItemView.feed()
								case .timeline:
									IconNavBarItemView.timeline()
								case .reels:
									IconNavBarItemView.reels()
								case .userProfile:
									Group {
										if currentTab == .userProfile {
											AvatarImageView(title: store.authenticatedUser.avatarName, size: .small, url: store.authenticatedUser.avatarUrl)
												.padding(4)
												.overlay {
													Circle()
														.stroke(Assets.Colors.bodyColor, lineWidth: 2)
												}
										} else {
											AvatarImageView(title: store.authenticatedUser.avatarName, size: .small, url: store.authenticatedUser.avatarUrl)
										}
									}
									.animation(.snappy, value: currentTab)
								}
							}
							.noneEffect()
							.foregroundStyle(currentTab == tab ? Assets.Colors.bodyColor : Color(.systemGray5))
							.frame(maxWidth: .infinity)
						}
					}
					.frame(height: 56)
					.background(Assets.Colors.appBarBackgroundColor)
				}
			}
			.toolbar(.hidden, for: .navigationBar)
			.safeAreaInset(edge: .bottom) {
				if store.showAppLoadingIndeterminate {
					AppLoadingIndeterminateView()
						.transition(.move(edge: .bottom).combined(with: .opacity))
						.frame(maxWidth: .infinity)
						.frame(height: 3)
				}
			}
		}
	}
}
