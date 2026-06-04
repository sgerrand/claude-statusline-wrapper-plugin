# Changelog

## [0.2.0](https://github.com/sgerrand/claude-statusline-wrapper-plugin/compare/v0.1.0...v0.2.0) (2026-06-04)


### Features

* add config loader and default fallback source ([449b4b1](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/449b4b120cba7f828888724b34f2d66ef6f7a52e))
* add parallel composition and wrapper entrypoint ([3daff15](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/3daff15bb8967221d025416a5dee7e868c6788e0))
* add plugin manifest and scaffolding ([0fc5798](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/0fc5798c332cc1fab3b2c3314117f73490cf8a52))
* **cache:** add 1s output cache keyed by session and context ([27f6a08](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/27f6a08842e499559a1051c3324e7bb852b3fc0f))
* **cli:** add --version, --diag, --help flags ([322db83](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/322db8337d5d02e238e7b9c302fcecae3c006468))
* **commands:** add /statusline-wrapper:configure slash command ([81b9b6c](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/81b9b6c4dbb382728e8409d94307e5a8c3de031d))
* **compose:** cap source output bytes and truncate multi-line stdout ([359dc91](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/359dc91d8a15539e339be4a2351b6ff4d74b308b))
* **config:** reject unsupported schema versions ([4a9ea81](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/4a9ea811fd89e669cd45881b84bda870ddbe6a44))


### Bug Fixes

* **cache:** include config mtime in key, unique tmp per writer ([92245f4](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/92245f4bb5c0bcefd19fe0317c4cd5c895547f9d))
* **config:** validate numeric timeouts and surface load failures ([dcf8972](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/dcf8972988a0fb6f0d411685153189dfdf367520))
* **config:** validate onError and fallback enums ([0243add](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/0243add1fdb22641d84b73749615201f1f21a0f4))
* **log:** make rotation race-safe via mkdir mutex ([f94c183](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/f94c1830ce7cf72bf12313ed9c5d4ddc4c27dff4))
* respect explicit passStdin: false in source config ([102ea2d](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/102ea2d02811f44d5836090dff97280eb76af8c3))


### Performance Improvements

* **compose:** drop awk fork for ms-to-seconds conversion ([599b253](https://github.com/sgerrand/claude-statusline-wrapper-plugin/commit/599b25314ae3fb0c93af562407607195b723b65b))
