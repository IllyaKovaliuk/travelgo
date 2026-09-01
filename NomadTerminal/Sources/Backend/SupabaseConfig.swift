import Foundation
import Supabase

/// Single shared client. The publishable key below is meant to ship in
/// client apps — it's authorization-scoped by Row Level Security on the
/// server, not by secrecy. Never put the `service_role`/secret key here.
enum SupabaseConfig {
    static let projectURL = URL(string: "https://smdnbjvelqsgjoubognc.supabase.co")!
    static let publishableKey = "sb_publishable_1b_hZ_62coFAs3OgR7lPCQ_ZjguD4bw"
}

let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.projectURL,
    supabaseKey: SupabaseConfig.publishableKey
)
