# 🧐 Cyte

🚧 Work in progress - this is beta software, use with care

A background screen recorder for easy history search. 
If you choose to supply an OpenAI key, or a local language model like LLaMA, it can act as a knowledge base. Be aware that transcriptions will be sent to OpenAI when you chat if you provide an OpenAI API key.

![Cyte Screenshot](assets/images/cyte.gif)

## Uses

### 🧠 Train-of-thought recovery

Autosave isn’t always an option, in those cases you can easily recover your train of thought, a screenshot to use as a stencil, or extracted copy from memories recorded.

### 🌏 Search across applications

A lot of research involves collating information from multiple sources; internal tools like confluence, websites like wikipedia, pdf and doc files etc; When searching for something we don’t always remember the source (or it's at the tip of your tongue)

## Features

> - When no OpenAI key is supplied, and browser context awareness is disabled, Cyte is completely private, data is stored on disk only, no outside connections are made
> - Pause/Restart recording easily
> - Set applications that are not to be recorded (while taking keystrokes)
> - Chat your data; ask questions about work you've done

## Contributing

* Generally, try to follow the surrounding style, but it's fine if you don't, linters can fix that stuff
* Fork this repository, make any changes, and when you're happy, submit a PR and we can review it together
* I prefer to keep documentation in the code (that's the most likely place it won't go too stale IMO). If something needs more documentation to be easily understandable, raise an issue and I'll revise it. I'll also write some technical deep dives on architectural stuff post 1.0
* Everything in the pipeline is tracked in the Issues tab. Unless assigned to someone, feel free to pick any issue up. Just drop a note in the Issue so no one else takes a run at the same time
* If you have a feature suggestion, please submit it in the issues tab for discussion. Let's make the app better for everyone
* mainline is latest - if you want a 'stable' (as stable as pre-release can be) branch use a tag

### Issues

- App sandbox is disabled to allow file tracking; [instead should request document permissions](https://stackoverflow.com/a/70972475)
- Some results from searching fail to highlight the result snippet
- Keyboard navigation events: Return to open selected episode, escape to pop timeline view
- Apply object recognition per frame
- Test automation
- Unit tests for Memory
- Sync between Cytes
- Chat this episode
- Split episodes
- iPad support

## Credits

Thanks to these great open source projects:

- [DiffMatchPatch](https://github.com/google/diff-match-patch): Used to differentiate unchanged and changed text from OCR (macOS)
- [SwiftDiff](https://github.com/turbolent/SwiftDiff): Used to differentiate unchanged and changed text from OCR (iOS)
- [AXSwift](https://github.com/tmandry/AXSwift): Used for browser context awareness
- [KeychainSwift](https://github.com/evgenyneu/keychain-swift): Used to securely store API keys in the Apple Keychain Manager
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift): Used for the text search functionality
- [XCGLogger](https://github.com/DaveWoodCom/XCGLogger): Used to save debug logs to disk
- [llama.cpp](https://github.com/ggerganov/llama.cpp): Used to load and run LLMs for chat when a local model is provided
- [MacPaw OpenAI](https://github.com/MacPaw/OpenAI): Used to run LLMs for chat when OpenAI API enabled
- [RNCryptor](https://github.com/RNCryptor/RNCryptor): Used to encrypt video files on disk
- [sqlcipher](https://www.zetetic.net/sqlcipher/): Used to encrypt database on disk
