#  Reasoning about percieved inputs after they have been classified

## Feature Requests


## Issues


Replicates useful tools from langchain[https://github.com/hwchase17/langchain]

- Interfacing with LLMs through a common facade
- Automatic formatting of prompt templates
- Graph-like execution of interdependent LLM calls
- Various utility functions useful in LLM graphs
- Agents which implement ReAct, CoT and other active behaviour[https://arxiv.org/pdf/2210.03629.pdf]
- Embedding index which can work offline and online

## Update 1
Langchain is built on other tools like Unstructured and Deep Layout, which in turn rely on huggingface or pytorch, which are generally tougher to integrate with swift unless you know exactly what subset of features you need in production
So for now, the functionality will be exposed via websocket server as a research feature 
Indexing, OpenAI etc can all be handled relatively easily, however file decoding and visual embedding/classification are still a lot of effort. Hopefully turicreate or something else from Apple helps with this.  
I'm hopeful the community will create a Swift version of langchain, which can just be hooked up here. Or, if GPT4 is multimodal....

## Update 2
GPT4 is multimodal, plus has large enough context to not need anything but OCR as input, so have implemented the used functionality here in Swift. Had to patch the openai sdk to support streaming and moderation.
