import AppUI
import ComposableArchitecture
import Foundation
import InstaBlocks
import Kingfisher
import Shared
import SwiftUI
import UserClient

@Reducer
public struct PostFooterReducer {
	public init() {}
	@ObservableState
	public struct State: Equatable {
		var profileUserId: String
		var block: InstaBlockWrapper
		var isLiked: Bool
		var likesCount: Int
		var commentsCount: Int
		var mediaUrls: [String]
		var likersInFollowings: [User]
		@Shared var currentMediaIndex: Int
		public init(
			block: InstaBlockWrapper,
			profileUserId: String,
			isLiked: Bool,
			likesCount: Int,
			commentsCount: Int,
			mediaUrls: [String],
			likersInFollowings: [User],
			currentMediaIndex: Shared<Int>
		) {
			self.block = block
			self.profileUserId = profileUserId
			self.isLiked = isLiked
			self.likesCount = likesCount
			self.commentsCount = commentsCount
			self.mediaUrls = mediaUrls
			self.likersInFollowings = likersInFollowings
			self._currentMediaIndex = currentMediaIndex
		}
		
		var firstLikerInFollowings: User? {
			likersInFollowings.first
		}

		var suffixLikersCount: Int {
			likersInFollowings.count - 1
		}
	}

	public enum Action: BindableAction {
		case binding(BindingAction<State>)
		case onTapLikeButton
		case likesCountUpdated(Int)
		case commentsCountUpdated(Int)
		case isLikedUpdated(Bool)
		case likersInFollowingsUpdated([User])
		case task
	}

	private enum Cancel: Hashable {
		case subscriptions
	}
	
	@Dependency(\.userClient.databaseClient) var databaseClient

	public var body: some ReducerOf<Self> {
		BindingReducer()
		Reduce { state, action in
			switch action {
			case .task:
				return .run { [block = state.block.block, profileUserId = state.profileUserId] send in
					await withThrowingTaskGroup(of: Void.self) { group in
						group.addTask {
							let likersInFollowings = try await databaseClient.getPostLikersInFollowings(block.id, 0, 10)
							await send(.likersInFollowingsUpdated(likersInFollowings))
						}
						group.addTask {
							await subscriptions(send: send, post: block, profileUserId: profileUserId)
						}
					}
				}
				.cancellable(id: Cancel.subscriptions, cancelInFlight: true)
			case .binding:
				return .none
			case .onTapLikeButton:
				return .run { [postId = state.block.id] _ in
					try await databaseClient.likePost(postId, true)
				}
			case let .likesCountUpdated(likesCount):
				state.likesCount = likesCount
				return .none
			case let .commentsCountUpdated(commentsCount):
				state.commentsCount = commentsCount
				return .none
			case let .isLikedUpdated(isLiked):
				state.isLiked = isLiked
				return .none
			case let .likersInFollowingsUpdated(likersInFollowings):
				state.likersInFollowings = likersInFollowings
				return .none
			}
		}
	}

	private func subscriptions(send: Send<Action>, post: any PostBlock, profileUserId: String) async {
		async let likesCount: Void = {
			for await likesCount in await databaseClient.likesOfPost(post.id, true) {
				await send(.likesCountUpdated(likesCount))
			}
		}()
		async let commentsCount: Void = {
			for await commentsCount in await databaseClient.postCommentsCount(post.id) {
				await send(.commentsCountUpdated(commentsCount))
			}
		}()
		async let isLiked: Void = {
			for await isLiked in await databaseClient.isLiked(post.id, nil, true) {
				await send(.isLikedUpdated(isLiked))
			}
		}()
		
		_ = await (likesCount, commentsCount, isLiked)
	}
}

public struct PostFooterView: View {
	@Bindable var store: StoreOf<PostFooterReducer>
	@Environment(\.colorScheme) var colorScheme
	@Environment(\.textTheme) var textTheme
	public init(store: StoreOf<PostFooterReducer>) {
		self.store = store
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: AppSpacing.sm) {
			if store.block.isSponsored {
				Color.blue
					.frame(maxWidth: .infinity)
					.frame(height: 30)
					.padding(.bottom, AppSpacing.sm)
			}
			
			HStack(spacing: AppSpacing.lg) {
				likeButton()
				commentButton()
				shareButton()
				Spacer()
				bookmarkButton()
			}
			.overlay(alignment: .center) {
				if store.mediaUrls.count > 1 {
					DotIndicator(totalCount: store.mediaUrls.count, currentIndex: $store.currentMediaIndex)
				}
			}
			.padding(.top, store.block.isSponsored ? 0 : AppSpacing.sm)
			.padding(.horizontal, AppSpacing.md)
			
			if store.likesCount > 0 {
				likers()
					.padding(.horizontal, AppSpacing.lg)
					.transition(.move(edge: .top))
			}
			PostCaption(
				username: store.block.author.username,
				caption: store.block.caption
			)
			.padding(.horizontal, AppSpacing.lg)
			Divider()
		}
		.task {
			await store.send(.task).finish()
		}
	}
	
	private var likersInFollowingWidth: CGFloat {
		switch store.likersInFollowings.count {
		case 1: return 28
		case 2: return 44
		default: return 60
		}
	}
	
	@ViewBuilder
	private func likeButton() -> some View {
		Button {
			store.send(.onTapLikeButton)
		} label: {
			Image(systemName: store.isLiked ? "heart.fill" : "heart")
				.imageScale(.large)
				.foregroundStyle(store.isLiked ? Assets.Colors.red : Assets.Colors.bodyColor)
				.bold()
				.contentShape(.rect)
		}
		.scaleEffect(config: ButtonAnimationConfig(scale: .xs))
		.frame(width: AppSize.iconSize, height: AppSize.iconSize)
	}
	
	@ViewBuilder
	private func commentButton() -> some View {
		Button {} label: {
			Image(systemName: "message")
				.scaleEffect(x: -1, y: 1)
				.imageScale(.large)
				.foregroundStyle(Assets.Colors.bodyColor)
				.bold()
				.contentShape(.rect)
		}
		.scaleEffect(config: ButtonAnimationConfig(scale: .xs))
		.frame(width: AppSize.iconSize, height: AppSize.iconSize)
	}
	
	@ViewBuilder
	private func shareButton() -> some View {
		Button {} label: {
			Image(systemName: "arrowshape.turn.up.right")
				.imageScale(.large)
				.foregroundStyle(Assets.Colors.bodyColor)
				.bold()
				.contentShape(.rect)
		}
		.scaleEffect(config: ButtonAnimationConfig(scale: .xs))
		.frame(width: AppSize.iconSize, height: AppSize.iconSize)
	}
	
	@ViewBuilder
	private func bookmarkButton() -> some View {
		Button {} label: {
			Image(systemName: "bookmark")
				.imageScale(.large)
				.foregroundStyle(Assets.Colors.bodyColor)
				.bold()
				.contentShape(.rect)
		}
		.scaleEffect(config: ButtonAnimationConfig(scale: .xs))
		.frame(width: AppSize.iconSize, height: AppSize.iconSize)
	}
	
	@ViewBuilder
	private func likers() -> some View {
		HStack(spacing: AppSpacing.sm) {
			if store.likersInFollowings.count > 0 {
				HStack(spacing: 0) {
					ForEach(Array(store.likersInFollowings.enumerated()), id: \.element.id) { index, user in
						KFImage.url(URL(string: user.avatarUrl ?? ""))
							.placeholder {
								Assets.Images.profilePhoto
									.view(width: 24, height: 24)
									.padding(AppSpacing.xxs)
									.overlay {
										Circle()
											.stroke(Assets.Colors.appBarSurfaceTintColor, lineWidth: 2)
									}
									.clipShape(.circle)
									.frame(width: 28, height: 28)
							}
							.resizable()
							.fade(duration: 0.2)
							.scaledToFill()
							.clipShape(.circle)
							.frame(width: 28, height: 28)
							.offset(x: CGFloat(index) * (-14))
							.zIndex(Double(store.likersInFollowings.count - 1) - Double(index))
					}
				}
				.frame(width: likersInFollowingWidth, height: 28)
			}
			Group {
				if let firstLiker = store.firstLikerInFollowings {
					Text("Liked by \(firstLiker.displayFullName)")
						.bold()
					if store.suffixLikersCount > 0 {
						Text("and")
							+
							Text(" \(store.suffixLikersCount) others")
							.bold()
					}
				} else {
					Text("\(store.likesCount) ")
						.bold()
					+ Text("Likes")
				}
			}
			.font(textTheme.titleMedium.font)
			.foregroundStyle(Assets.Colors.bodyColor)
			.contentTransition(.numericText())
			Spacer()
		}
		.padding(.vertical, AppSpacing.sm)
	}
}
