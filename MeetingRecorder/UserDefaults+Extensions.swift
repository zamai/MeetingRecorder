import Foundation

extension UserDefaults {
    private enum Keys {
        static let destinationFolderBookmark = "destinationFolderBookmark"
    }

    var destinationFolderURL: URL? {
        get {
            guard let bookmarkData = data(forKey: Keys.destinationFolderBookmark) else {
                return nil
            }
            
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
                return nil
            }
            
            if isStale {
                // Handle stale bookmark if needed
                return nil
            }
            
            return url
        }
        set {
            guard let url = newValue else {
                removeObject(forKey: Keys.destinationFolderBookmark)
                return
            }
            
            guard let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
                return
            }
            
            set(bookmarkData, forKey: Keys.destinationFolderBookmark)
        }
    }
}