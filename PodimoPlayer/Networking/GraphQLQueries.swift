import Foundation

enum GraphQLQueries {
    static let followed = """
    query EpisodesFollowedResultsQuery($limit: Int) {
        podcastEpisodesFollowed(onlyNew: true, limit: $limit, offset: 0) {
            ...EpisodeBaseFragment
            __typename
        }
    }

    fragment EpisodeBaseFragment on PodcastEpisode {
      id
      publishDatetime
      title
      artist
      image { url __typename }
      podcastId
      podcastName
      description
      duration
      isMarkedAsPlayed
      hasVideo
      accessLevels
      ...PodcastEpisodeUserProgress
      __typename
    }

    fragment PodcastEpisodeUserProgress on PodcastEpisode {
      userProgress {
          progress
          listenTime
          lastListenDatetime
          __typename
      }
      __typename
    }
    """

    static let mediaURL = """
    query ShortLivedPodcastMediaUrlQuery($podcastId: String!, $episodeId: String!) {
        podcastEpisodeStreamMediaById(podcastId: $podcastId, episodeId: $episodeId) {
            url
            __typename
        }
    }
    """

    static let library = """
    query LibrarySavedItemsResultsQuery($podcastsSorting: PodcastFollowSortingType) {
        audiobooksUserLibrary(offset: 0, sorting: DATE_ADDED) {
            ...AudiobookBaseFragment
            __typename
        }
        podcastsFollowed(offset: 0, type: ALL, sorting: $podcastsSorting) {
            ...PodcastBaseFragment
            __typename
        }
    }

    fragment AudiobookBaseFragment on Audiobook {
        id
        title
        accessLevels
        authors {
            name
            __typename
        }
        duration
        ...AudiobookCoverImageFragment
        ...AudioBookUserStateFragment
        __typename
    }

    fragment AudiobookCoverImageFragment on Audiobook {
        coverImage {
            mainColor
            url
            __typename
        }
        __typename
    }

    fragment AudioBookUserStateFragment on Audiobook {
        userState {
            isAddedToLibrary
            isMarkedAsPlayed
            userProgress {
                lastListenDatetime
                listenTime
                progress
                __typename
            }
            __typename
        }
        __typename
    }

    fragment PodcastBaseFragment on Podcast {
        authorName
        hasVideo
        id
        podcastType
        title
        ...PodcastUserStatsFragment
        ...PodcastImagesFragment
        ...PodcastFeaturesStatusFragment
        __typename
    }

    fragment PodcastUserStatsFragment on Podcast {
        userStats {
            isFollowing
            __typename
        }
        __typename
    }

    fragment PodcastImagesFragment on Podcast {
        images {
            coverImageUrl
            artworkOutstretchedUrl
            artworkPremiumUrl
            __typename
        }
        __typename
    }

    fragment PodcastFeaturesStatusFragment on Podcast {
        featuresStatus {
            badge
            __typename
        }
        __typename
    }
    """

    static let episodes = """
    query PodcastEpisodesResultsQuery($podcastId: String!, $offset: Int, $limit: Int, $sorting: PodcastEpisodeSorting) {
     podcastEpisodes(
     podcastId: $podcastId
     offset: $offset
     limit: $limit
     converted: true
     published: true
     sorting: $sorting
     ) {
     ...PodcastEpisodeFragment
     __typename
     }
    }

    fragment PodcastEpisodeFragment on PodcastEpisode {
     id
     podcastId
     podcastName
     title
     imageUrl
     premiumBadge
     description
     publishDatetime
     authorName
     accessLevel
     accessLevels
     duration
     isMarkedAsPlayed
     hasVideo
     ...PodcastEpisodeUserProgress
     ...PodcastEpisodeRatingScoreFragment
     __typename
    }

    fragment PodcastEpisodeUserProgress on PodcastEpisode {
     userProgress {
     progress
     listenTime
     lastListenDatetime
     __typename
     }
     __typename
    }

    fragment PodcastEpisodeRatingScoreFragment on PodcastEpisode {
     ratingScore {
     score
     total
     __typename
     }
     __typename
    }
    """
}