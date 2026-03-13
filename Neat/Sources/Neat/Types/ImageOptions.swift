public enum ImageLoading: String {
    case deferred = "lazy"
    case immediate = "eager"
}

public enum ImageDecoding: String {
    case asynchronous = "async"
    case synchronous = "sync"
    case automatic = "auto"
}

public enum ImageFetchPriority: String {
    case high
    case low
    case automatic = "auto"
}
