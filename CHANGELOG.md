# 0.2.0 (Oct 2, 2026)
* Pinned `nullstone-io/ns` provider to `~> 0.13.0`.
* Replaced `ns_env_variables` and `ns_secret_keys` with the layered `ns_env_layout`, `ns_env_values`, and `ns_env_platform_data` data sources to aggregate environment variables and secrets.
* Emitted the `env` platform data record, including the source of each variable and the Secret Manager id of each managed secret.
* Upgraded capability scaffolding to emit `capability` on capability outputs and `cap_prefixes`.

# 0.1.0 (Unreleased)
* Initial release
