//
//  Agent.swift
//  Cyte
//
//  Created by Shaun Narayan on 3/03/23.
//

import Foundation
import CoreGraphics
import NaturalLanguage
import OpenAI
import KeychainSwift
import XCGLogger
import llama
import SwiftUI

class Agent : ObservableObject, EventSourceDelegate {
    static let shared : Agent = Agent()
    
    private var openAIClient: OpenAI?
    private let keychain = KeychainSwift()
    @Published var isSetup: Bool = false
    
    // The prompt used when question answering
    static let promptTemplate = """
    Use the following pieces of context to answer the question at the end. The context includes transcriptions of my computer screen from running OCR on screenshots taken for every two seconds of computer activity. If you don't know the answer, just say that you don't know, don't try to make up an answer.
        Current Date/Time:
        {current}
        Context:
        {context}
        Question:
        {question}
        Helpful Answer:
    """
    
    static let contextTemplate = """
    Results from OCR on a screenshot taken at {when}:
    {ocr}
    
    """
    // Prompt used when chatting
    static let chatPromptTemplate = """
    Assistant is a large language model.

    Assistant is designed to be able to assist with a wide range of tasks, from answering simple questions to providing in-depth explanations and discussions on a wide range of topics. As a language model, Assistant is able to generate human-like text based on the input it receives, allowing it to engage in natural-sounding conversations and provide responses that are coherent and relevant to the topic at hand.

    Assistant is constantly learning and improving, and its capabilities are constantly evolving. It is able to process and understand large amounts of text, and can use this knowledge to provide accurate and informative responses to a wide range of questions. Additionally, Assistant is able to generate its own text based on the input it receives, allowing it to engage in discussions and provide explanations and descriptions on a wide range of topics.

    Overall, Assistant is a powerful tool that can help with a wide range of tasks and provide valuable insights and information on a wide range of topics. Whether you need help with a specific question or just want to have a conversation about a particular topic, Assistant is here to assist.

    {history}
    Human: {question}
    Assistant:
    """
    
    @Published public var chatLog : [(String, String, String)] = []
    private var llama: OpaquePointer?
    
    init() {
        setup()
    }
    
    ///
    /// Creates a openai api wrapper client with the given key, updating
    /// a user preference at the same time
    ///
    func setup(key: String? = nil) {
        if key != nil {
            keychain.set(key!, forKey: "CYTE_LLM_KEY")
        }
        let apiKey = key != nil ? key : keychain.get("CYTE_LLM_KEY")
        if apiKey != nil {
            if FileManager.default.fileExists(atPath: apiKey!) {
                llama = llama_init_from_file(apiKey, llama_context_default_params())
                isSetup = true
                log.info("Setup llama")
            } else {
                openAIClient = OpenAI(apiToken: apiKey!, callback: self)
                isSetup = true
                log.info("Setup OpenAI")
            }
        } else {
            teardown()
        }
    }
    
    func teardown() {
        reset()
        if llama != nil {
            llama_free(llama)
            llama = nil
        } else {
            openAIClient = nil
        }
        isSetup = false
    }
    
    ///
    /// Check the supplied text against the free moderation endpoint before sending to
    /// a charging endpoint
    ///
    func isFlagged(input: String) async -> Bool {
        if llama != nil {
            return false
        }
        let query = OpenAI.ModerationQuery(input: input, model: .textModerationLatest)
        var response: Bool = false
        do {
            let result = try await openAIClient!.moderations(query: query)
            response = result.results[0].flagged
        } catch {}
        return response
    }
    
    ///
    /// Embeds the given string
    ///
    func embed(input: String) async -> [Double]? {
        if await isFlagged(input: input) { return nil }
        var response: [Double]? = nil
        if llama != nil {
            response = []
            await query(input: input)
            let raw = llama_get_embeddings(llama)
            for i in 0..<Int(llama_n_embd(llama)) {
                response!.append(Double(raw![i]))
            }
        } else {
            let query = OpenAI.EmbeddingsQuery(model: .textEmbeddingAda, input: input)
            do {
                let result = try await openAIClient!.embeddings(query: query)
                response = result.data[0].embedding
            } catch {}
        }
        return response
    }
    
    ///
    /// Requests a streaming completion for the fully formatted prompt
    ///
    func query(input: String) async -> Void {
        if await isFlagged(input: input) { return }
        if llama != nil {
            let temperature: Float = 1.0
            let nThreads: Int32 = Int32(ProcessInfo.processInfo.activeProcessorCount)
            let topK: Int32 = 40
            let topP: Float = 1.0
            var tokens: Array<llama_token> = []
            let promptTokens = Array<llama_token>(unsafeUninitializedCapacity: input.utf8.count) { buffer, initializedCount in
                initializedCount = Int(llama_tokenize(llama, input, buffer.baseAddress, Int32(buffer.count), true))
            }

            let bufferPointer: UnsafeBufferPointer<llama_token> = promptTokens.withUnsafeBufferPointer { bufferPointer in
                return bufferPointer
            }
            let _ = DispatchQueue.main.sync {
                llama_eval(llama, bufferPointer.baseAddress, Int32(promptTokens.count), 0, nThreads)
            }
            tokens.insert(contentsOf: promptTokens, at: 0)
            
            let contextLength = llama_n_ctx(llama)
            while (tokens.count < contextLength) && chatLog.count > 0 {
                let n_vocab: Int32 = llama_n_vocab(llama)
                let logits = llama_get_logits(llama)
                var candidates: Array<llama_token_data> = []
                for i in 0..<n_vocab {
                    candidates.append(llama_token_data(id: i, logit: logits![Int(i)], p: 0.0))
                }
                let candidatePointer: UnsafeMutableBufferPointer<llama_token_data> = candidates.withUnsafeMutableBufferPointer { bp in
                    return bp
                }
                var tokenData: llama_token_data_array = llama_token_data_array(data: candidatePointer.baseAddress, size: Int(n_vocab), sorted: false)
                
                llama_sample_top_k(llama, &tokenData, topK, 1);
                llama_sample_top_p(llama, &tokenData, topP, 1);
                llama_sample_temperature(llama, &tokenData, temperature);
                var token = llama_sample_token(llama, &tokenData);
                if token == llama_token_eos() {
                    break
                }
                let thisResult = String(cString: llama_token_to_str(llama, token))
                let current_tokens = tokens
                DispatchQueue.main.sync {
                    if chatLog.count != 0 {
                        onNewToken(token: thisResult)
                        llama_eval(llama, &token, 1, Int32(current_tokens.count), nThreads)
                    }
                }
                tokens.append(token)
            }
        } else {
            let query = OpenAI.ChatQuery(model: .gpt4, messages: [.init(role: "user", content: input)], stream: true)
            openAIClient!.chats(query: query)
        }
    }
    
    ///
    /// Called for every new token in a completion
    ///
    func onNewToken(token: String) {
        let chatId = chatLog.lastIndex(where: { log in
            return log.0 == "bot"
        })
        withAnimation(.easeInOut(duration: 0.3)) {
            chatLog[chatId!].2.append(token.replacingOccurrences(of: "\\n", with: "\n"))
        }
    }
    
    func onStreamDone() {
        let chatId = chatLog.lastIndex(where: { log in
            return log.0 == "bot"
        })
        chatLog[chatId!].1 = "gpt4"
    }
    
    func index(path: URL) {
        // @todo if the file type is supported, decode it and embed
    }
    
    ///
    /// Stop any pending requests and clear state
    ///
    func reset() {
        if openAIClient != nil {
            openAIClient!.stop()
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            chatLog.removeAll()
        }
    }
    
    ///
    /// Given a user question, apply a prompt template and optionally stuff with context before
    /// initiating a request
    ///
    func query(request: String, over: [CyteInterval]) async {
        var _cleanRequest = request
        var force_chat = false
        if request.lowercased().starts(with: "chat ") {
            force_chat = true
            _cleanRequest = String(request.dropFirst("chat ".count))
        }
        let cleanRequest = _cleanRequest
        DispatchQueue.main.sync {
            withAnimation(.easeIn(duration: 0.3)) {
                chatLog.append(("user", "", cleanRequest))
                chatLog.append(("bot", "", ""))
            }
        }
        
        var context: String = ""
        // @todo improve with actual tokenization, and maybe a min limit to save for return tokens
        // for now, using a heuristic of 3 chars per token (vs ~4 in reality) leaves on avg ~25%
        // of the window for response
        let contextTokenLength = (llama != nil ? Int(llama_n_ctx(llama)) : 8000)
        let maxContextLength = (contextTokenLength * 3 /* rough token len */) - Agent.promptTemplate.count

        let intervals = over.count > 0 ? over : await Memory.shared.search(term: "")
        if intervals.count > 0 && !force_chat {
            for interval in intervals {
                if interval.document.count > 100 {
                    let new_context = Agent.contextTemplate.replacing("{when}", with: interval.from.formatted()).replacing("{ocr}", with: interval.document)
                    if context.count + new_context.count < maxContextLength {
                        context += new_context
                    }
                }
            }
            let prompt = Agent.promptTemplate.replacing("{current}", with: Date().formatted()).replacing("{context}", with: context).replacing("{question}", with: request)
            log.debug(prompt)
            await query(input: prompt)
        } else {
            var history: String = ""
            for chat in chatLog {
                history = """
                    \(history)
                    \(chat.0 == "bot" ? "Assistant: " : "Human: ")\(chat.2)
                """
            }
            let prompt = Agent.chatPromptTemplate.replacing("{history}", with: history).replacing("{question}", with: cleanRequest)
            log.debug(prompt)
            await query(input: prompt)
        }
    }
}
