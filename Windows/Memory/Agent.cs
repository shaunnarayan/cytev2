using Microsoft.UI.Xaml.Media.Imaging;
using OpenAI_API.Chat;
using OpenAI_API.Models;
using OpenAI_API.Moderation;
using OpenAI_API;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using LLama.Native;

namespace CyteEncoder
{
    public class ChatItem
    {
        public string message { get; set; }
        public BitmapImage icon { get; set; } = new BitmapImage();
        public bool fromUser = true;

        public ChatItem(BitmapImage _icon, string message, bool fromUser = true)
        {
            icon = _icon;
            this.message = message;
            this.fromUser = fromUser;
        }
    }

    internal class Agent
    {
        private static readonly Lazy<Agent> lazy = new Lazy<Agent>(() => new Agent());
        public List<ChatItem> chatLog { get; set; } = new List<ChatItem>();

        private static string promptTemplate = @"
        Use the following pieces of context to answer the question at the end. The context includes transcriptions of my computer screen from running OCR on screenshots taken for every two seconds of computer activity. If you don't know the answer, just say that you don't know, don't try to make up an answer.
        Current Date/Time:
        {current}
        Context:
        {context}
        Question:
        {question}
        Helpful Answer:";
        private static string contextTemplate = @"
        Results from OCR on a screenshot taken at {when}:
        {ocr}";
        private static string chatPromptTemplate = @"
        Assistant is a large language model.
        Assistant is designed to be able to assist with a wide range of tasks, from answering simple questions to providing in-depth explanations and discussions on a wide range of topics. As a language model, Assistant is able to generate human-like text based on the input it receives, allowing it to engage in natural-sounding conversations and provide responses that are coherent and relevant to the topic at hand.
        Assistant is constantly learning and improving, and its capabilities are constantly evolving. It is able to process and understand large amounts of text, and can use this knowledge to provide accurate and informative responses to a wide range of questions. Additionally, Assistant is able to generate its own text based on the input it receives, allowing it to engage in discussions and provide explanations and descriptions on a wide range of topics.
        Overall, Assistant is a powerful tool that can help with a wide range of tasks and provide valuable insights and information on a wide range of topics. Whether you need help with a specific question or just want to have a conversation about a particular topic, Assistant is here to assist.
        {history}
        Human: {question}
        Assistant:";
        public bool isSetup { get; set; } = false;
        private OpenAIAPI openAI = null;
        private LLama.Native.SafeLLamaContextHandle llama = null;
        private Model openAIModel = Model.ChatGPTTurbo;
        public delegate void UpdateChat(List<ChatItem> log);
        private UpdateChat updateChat = null;

        public static Agent Instance
        {
            get { return lazy.Value; }
        }

        private Agent()
        {

        }

        private async Task<bool> IsFlagged(string query)
        {
            var result = await openAI.Moderation.CallModerationAsync(new ModerationRequest(query, Model.TextModerationLatest));
            return result.Results[0].Flagged;
        }

        private List<LLamaTokenData> LlamaVocab()
        {
            var n_vocab = NativeApi.llama_n_vocab(llama);
            Span<float> logits = SamplingApi.llama_get_logits(llama, n_vocab);
            var candidates = new List<LLamaTokenData>();
            candidates.Capacity = n_vocab;
            for (Int32 token_id = 0; token_id < n_vocab; token_id++)
            {
                candidates.Add(new LLamaTokenData(token_id, logits[token_id], 0.0f));
            }
            //candidates.Add(new LLamaTokenData(NativeApi.llama_token_eos(), 0.0f, 0.0f));
            return candidates;
        }

        private void CompleteLlama(string query)
        {
            float temperature = 1.0f;
            int threads = Environment.ProcessorCount - 1;
            int topK = 40;
            float topP = 1.0f;

            List<Int32> tokens = SamplingApi.llama_tokenize(llama, query, true, "UTF-8");
            NativeApi.llama_eval(llama, tokens.ToArray(), tokens.Count, 0, threads);

            int contextLength = NativeApi.llama_n_ctx(llama);
            while ((tokens.Count < contextLength) && chatLog.Count > 0)
            {
                var candidates = LlamaVocab();
                LLamaTokenDataArray candidates_p = new LLamaTokenDataArray(candidates.ToArray(), (ulong)candidates.Count, false);

                SamplingApi.llama_sample_top_k(llama, candidates_p, topK, 1);
                SamplingApi.llama_sample_top_p(llama, candidates_p, topP, 1);
                SamplingApi.llama_sample_temperature(llama, candidates_p, temperature);
                var token = SamplingApi.llama_sample_token(llama, candidates_p);
                if (token == NativeApi.llama_token_eos())
                {
                    break;
                }

                string text = Marshal.PtrToStringUTF8(NativeApi.llama_token_to_str(llama, token));

                chatLog[chatLog.Count - 1].message = chatLog[chatLog.Count - 1].message + text;
                updateChat(chatLog);

                tokens.Add(token);
                NativeApi.llama_eval(llama, tokens.TakeLast(1).ToArray(), 1, tokens.Count, threads);
            }
        }

        public async void Complete(string query)
        {
            if (llama != null)
            {
                CompleteLlama(query);
                return;
            }
            if (await IsFlagged(query))
            {
                return;
            }
            var chat = openAI.Chat.CreateConversation(new ChatRequest()
            {
                Model = Model.GPT4
            }
            );
            chat.AppendUserInput(query);

            await chat.StreamResponseFromChatbotAsync(res =>
            {
                chatLog[chatLog.Count - 1].message = chatLog[chatLog.Count - 1].message + res;
                Console.Write(res);
                updateChat(chatLog);
            });
        }

        public async Task<bool> Setup()
        {
            if (!isSetup)
            {
                var vault = new Windows.Security.Credentials.PasswordVault();
                var keys = vault.RetrieveAll();
                if (keys.Count > 0)
                {
                    var key = keys.First();
                    key.RetrievePassword();
                    var apiKey = key.Password;
                    try
                    {
                        var file = await Windows.Storage.StorageFile.GetFileFromPathAsync(apiKey);
                        if (file != null)
                        {
                            //llama = new LLamaModel(new LLamaParams(model: apiKey, n_ctx: 512, repeat_penalty: 1.0f));
                            llama = new LLama.Native.SafeLLamaContextHandle(NativeApi.llama_init_from_file(apiKey, NativeApi.llama_context_default_params()));
                            if (llama == null)
                            {
                                vault.Remove(key);
                                isSetup = false;
                                return isSetup;
                            }
                            isSetup = true;
                        }
                    }
                    catch
                    {
                        openAI = new OpenAIAPI(apiKey);
                        try
                        {
                            var models = await openAI.Models.GetModelsAsync();
                            foreach (var model in models)
                            {
                                if (model.ModelID == Model.GPT4_32k_Context)
                                {
                                    openAIModel = model;
                                    Debug.WriteLine("Using GPT4-32");
                                }
                                if (openAIModel != Model.GPT4_32k_Context && model.ModelID == Model.GPT4)
                                {
                                    openAIModel = model;
                                    Debug.WriteLine("Using GPT4-8");
                                }
                            }
                            isSetup = true;
                        }
                        catch 
                        {
                            isSetup = false;
                            vault.Remove(key);
                            return isSetup;
                        }
                    }
                    Reset();
                }
                return isSetup;
            }
            return isSetup;
        }

        public void Teardown()
        {
            openAI = null;
            if (llama != null)
            {
                llama.Dispose();
            }
            llama = null;
            isSetup = false;
        }

        public void Reset()
        {
            chatLog.Clear();
            updateChat = null;
        }

        public async void Query(UpdateChat onUpdate, Uri baseUri, string query, [ReadOnlyArray()] Interval[] over)
        {
            this.updateChat = onUpdate;
            string cleanQuery = query;
            bool forceChat = false;
            if (query.ToLower().StartsWith("chat "))
            {
                forceChat = true;
                cleanQuery = query.Remove(0, 5);
            }

            chatLog.Add(new ChatItem(new BitmapImage(new Uri(baseUri, "/Assets/user-circle-thin.png")), cleanQuery));
            chatLog.Add(new ChatItem(new BitmapImage(new Uri(baseUri, "/Assets/Square44x44Logo.targetsize-48.png")), "", false));
            updateChat(chatLog);

            string context = "";
            int contextWindowLength = llama != null ? 500 : 8000;
            int maxContextLength = contextWindowLength * 3 - promptTemplate.Length;
            Interval[] intervals = (over != null && over.Length > 0) ? over : Memory.Instance.Search("");
            if (intervals.Length > 0 && !forceChat)
            {
                foreach (var interval in intervals)
                {
                    if (interval.document.Length > 100)
                    {
                        string sub = contextTemplate.Replace("{when}", DateTime.FromFileTimeUtc(interval.from).ToString()).Replace("{ocr}", interval.document);
                        if (context.Length + sub.Length < maxContextLength)
                        {
                            context += sub;
                        }
                    }
                }
                string prompt = promptTemplate.Replace("{current}", DateTime.Now.ToString()).Replace("{context}", context).Replace("{question}", cleanQuery);
                Debug.WriteLine(prompt);
                Complete(prompt);
            }
            else
            {
                string history = "";
                foreach (var chat in chatLog)
                {
                    var person = chat.fromUser ? "Human: " : "Assistant: ";
                    history = $"{history}\n{person}{chat.message}";
                }
                string prompt = chatPromptTemplate.Replace("{history}", history).Replace("{question}", cleanQuery);
                Debug.WriteLine(prompt);
                Complete(prompt);
            }
        }
    }
}
