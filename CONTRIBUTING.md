# Contributing

Contributions improving reading comfort, Polish sentence segmentation, EPUB compatibility, accessibility, packaging, or localization are welcome.

Follow the README setup instructions. Native code is in `Sources/`, WebKit integration in `Resources/Web/reader.js`, and speech/import logic in `Resources/Engine/worker.py`.

Run `python3 -m unittest discover -s Tests -v` and build the app. When relevant, manually test playback, pause/resume, sentence skipping, narrator following, appearance changes, search, annotations, and position restoration after restart.

Use generated or openly licensed test books. Never commit personal books, recordings, library data, private paths, credentials, build outputs, or runtime environments.

Keep documentation and commit messages in English. The app UI remains Polish. Explain concrete before/after behavior and relevant checks in pull requests.

Original contributions are accepted under MIT. Preserve third-party attribution and licenses. Keep vendored code changes minimal and record them with the upstream revision in the notices.
