import Foundation
import Supabase

enum SupabaseService {
    static let projectURL = URL(string: "https://kzwyweglrzcnxcpxnfuf.supabase.co")!

    static let client = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: "sb_publishable_taO9kxbl5rYmZiFvWlI75g_JZNGzv5b"
    )
}
