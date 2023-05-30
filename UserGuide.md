# User guide

## Quickstart

- To get started, [download Cyte](https://cyte.io/) or follow the instructions for your platform below to build it locally.

### MacOS users only

- Unzip the app and move it into your Applications folder (overwrite any previous version of Cyte). This isn't necessary but it does make it less likely you'll run into any issues.
- Open Cyte.app from your applications folder. You'll see a search bar, some buttons, and a big empty area where your recordings will show.
- You should see a dialog saying Cyte wants to record your screen, and ask you to grant permission. If it doesn't appear, open System Settings -> Privacy and Security -> Screen Recording, press the plus icon and select Cyte from the Applications folder

### Windows users only

- Right click the downloaded zip file and select 'Extract all'
- Double click the file ending with '.msix' and select Install.
- Select launch once installation completes. You'll see a search bar, some buttons, and a big empty area where your recordings will show.
- You should see a dialog saying Cyte wants to record your screen, and ask you to grant permission.
- Next you will be asked if you would like to allow Cyte to record without a border around your entire screen - allow this if you'd like.
- Now you'll see a dialog asking you to allow Cyte to access process diagnostic info - this is needed to track the active application during recording

### All Platforms

- At this point, if you'd like to review your settings, click the cog icon
- - Cyte can use a lot of disk space, depending on your screen resolution and other factors. You can choose how long to keep recordings around for, and where to store them incase you want to use another drive. As a rule of thumb, Cyte will take around 100MB per hour recorded on an average setup
- - You can also enter your OpenAI API key or llama.cpp model, please read the section on chat for more info about this. On macOS, when you next start Cyte, you will be asked to grant permission for Cyte to access this key from Apple's keychain
- - On macOS, if you enable browser awareness (see below for more detail), you should see a dialog appear asking for access to Accessability services. If it doesn't appear, open System Settings -> Privacy and Security -> Accessability, press the plus icon and select Cyte from the Applications folder
- - Cyte will already have detected the applications currently running, and displayed them in a grid. Tick boxes for any applications you don't want Cyte to record. If your application isn't showing, press the add application button and select it there
- Once happy with your setup, press the back icon at the top of the window.
- When you need help remembering something, select the Cyte application in your dock or Menu Bar, or use Spotlight
- Type anything you do remember vaguely related to what you're looking for, and press return
- Look through the results and refresh your memory
- Press expand on any memory to view in more detail
- Press the button at the top right of the window to open the file related to the recording if it could be found (see below for more detail), otherwise there may be a blank space where the button would appear
- Press the back icon at the top of the window to return to the feed
- If you enabled chat features, you can type a question to get a quick answer related to the currently shown results (include a question mark, see below for more info) then press return or press the plane icon

### Building from source

#### MacOS

- Download and install [xcode](https://developer.apple.com/xcode/)
- Download and unzip or clone the [cytev2 repository](https://github.com/shaunnarayan/cytev2)
- Double click to open Cyte.xcodeproj inside the macOS+iOS directory
- Go to Project Settings -> Signing & Capabilities, and select your [development team](https://developer.apple.com/programs/) - you can sign up for free
- Update the signing certificate (you can use sign to run locally if you don't have a Apple developer membership)
- Press CMD + B to build, once complete, locate Cyte.app under 'Products' in the sidebar, right click and select Show in Finder
- You can now use the Cyte.app as per the Quickstart instructions above

#### Windows

- Download and install [Visual Studio Community Edition 2022](https://visualstudio.microsoft.com/vs/community/)
- Download and unzip or clone the [cytev2 repository](https://github.com/shaunnarayan/cytev2)
- Double click to open Cyte.sln inside the Windows directory
- Right-click the Cyte project, and select "Publish > Create App Packages", then follow through the prompts
- You can now use Cyte.msix as per the Quickstart instructions above

## Feed

- When no search terms or filters are applied, shows the last 30 days of recordings, from latest to oldest
- Each item in the grid has a full video preview player that can play, seek, and copy text
- Tapping the expand icon will take you to the timeline view, at the start of the recording
- Tapping the star icon will prevent the recording being deleted by any means until the star is tapped again
- The title of the recording is the title of the first window you opened in that application
- Right click the title to delete the memory
- Right click the tile to show the original recording file in the Finder. Do not delete/move this file from the finder, make a copy for your use.
- Recordings with less than 1 captured frame are not saved, in terms of time this translates to 2-4 seconds on M1/M2, and 4-8 seconds on Intel

## Search

- [Search is supported by SQLite’s FTS5.](https://github.com/shaunnarayan/cytev2/blob/main/Cyte/Retain/Memory.swift#:~:text=func%20search)
- Any search of at least 3 characters will be run as an [FTS query](https://www.sqlite.org/fts5.html#full_text_query_syntax), otherwise all results are returned.
- To run a search, press return after typing, or tap the button
- To clear your search filters, press the refresh button
- Tap the star to show only your starred recordings

### Semantic search

- You can add one or more ‘>’ characters to the start of your search to run an [inexact search](https://github.com/shaunnarayan/cytev2/blob/main/Cyte/Retain/Memory.swift#:~:text=expanding%20+=%201).
- Each character adds one alternative to every [verb/noun in the search term](https://developer.apple.com/documentation/naturallanguage/identifying_parts_of_speech)
- Alternatives are picked using [word embeddings](https://developer.apple.com/documentation/naturallanguage/nlembedding)

### Advanced search

- Click the dropdown button to filter results by date range or application/website
- Tap any application/website icon or text to apply it as a filter. Tap it again to remove.
- The total time recorded for the given filters and search is displayed
- You can then tap the delete icon to batch delete all the currently displayed recordings
- You can also tap the timelapse button to generate a 1 minute timelapse from the currently displayed recordings, if the total recording time displayed is less than 40 hours. Cancel the export by tapping the stop button next to the progress bar

## Timeline

- Displays the screenshot taken closest to any time in your history
- Scroll through time by dragging the slider underneath the screenshot
- Drag right to move back in time, left to go forward
- Once you arrive at your latest/oldest recording, you cannot drag any further
- The slider visually displays segments for each application/website used, using a colored bar with icon overlay
- Below the slider, the currently shown time is on the left, with how long ago it was on the right
- If Cyte was able to detect the document/link active, there will be a button in the toolbar on the right hand side to open the file/url

## Chat

- Any query ending with a '?' is communicated to your LLM if enabled
- Add 'chat ' before your question for a private, ChatGPT-like experience (no recording data is supplied to the LLM in this mode)
- Non chat requests will supply the currently displayed results to the LLM as context. if there are too many to fit the LLM's context and provide a response, results further down in the feed are ignored
- Press return in the top left of the chat window to return to the home screen

## Settings

- You can select where Cyte stores all data (except user preferences) by tapping the folder icon
- By default, all recordings and metadata are stored in your Application Support folder
- You can select how long Cyte retains recordings before automatically deleting them. Note this feature will not delete starred recordings.
- To enable chat your data, You can either;
- - paste your OpenAI API key if you want to enable GPT4 as your LLM. Your key is stored in Apples keychain and taken out of application memory once you press return or tap the tick icon
- - Paste the full path to a llama.cpp model file on your hard drive
- Enabling browser awareness for Chrome and Safari will prevent incognito and Private browsing windows from being recorded. This will also require making a network request to google for the favicon for sites visited
- Browser awareness will also attempt to track websites and divide your recordings by domain (e.g. all Twitter activity gets grouped under twitter.com)
- Tick any application/website in the disable recording section to prevent it being recorded, and also automatically delete any existing data stored for it
