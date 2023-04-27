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

## Development

Happy to accept PRs related to any of the following

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

- [SwiftDiff](https://github.com/turbolent/SwiftDiff): Used to differentiate unchanged and changed text from OCR
- [AXSwift](https://github.com/tmandry/AXSwift): Used for browser context awareness
- [KeychainSwift](https://github.com/evgenyneu/keychain-swift): Used to securely store API keys in the Apple Keychain Manager
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift): Used for the text search functionality
- [XCGLogger](https://github.com/DaveWoodCom/XCGLogger): Used to save debug logs to disk
- [llama.cpp](https://github.com/ggerganov/llama.cpp): Used to load and run LLMs for chat when a local model is provided
- [MacPaw OpenAI](https://github.com/MacPaw/OpenAI): Used to run LLMs for chat when OpenAI API enabled
