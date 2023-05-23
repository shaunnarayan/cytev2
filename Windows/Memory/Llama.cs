using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using LLama.Exceptions;
using LLama.Native;

namespace CyteEncoder
{
    using llama_token = Int32;

    [StructLayout(LayoutKind.Sequential)]
    internal struct LLamaTokenData
    {
        public int id;
        public float logit;
        public float p;

        public LLamaTokenData(int id, float logit, float p)
        {
            this.id = id;
            this.logit = logit;
            this.p = p;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct LLamaTokenDataArray
    {
        public Memory<LLamaTokenData> data;
        public ulong size;
        [MarshalAs(UnmanagedType.I1)]
        public bool sorted;

        public LLamaTokenDataArray(LLamaTokenData[] data, ulong size, bool sorted)
        {
            this.data = data;
            this.size = size;
            this.sorted = sorted;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct LLamaTokenDataArrayNative
    {
        public IntPtr data;
        public ulong size;
        public bool sorted;
    }

    internal unsafe class SamplingApi
    {
        public unsafe static Span<float> llama_get_logits(SafeLLamaContextHandle ctx, int length)
        {
            var logits = NativeApi.llama_get_logits(ctx);
            return new Span<float>(logits, length);
        }

        public static List<llama_token> llama_tokenize(SafeLLamaContextHandle ctx, string text, bool add_bos, string encoding)
        {
            var cnt = Encoding.GetEncoding(encoding).GetByteCount(text);
            llama_token[] res = new llama_token[cnt + (add_bos ? 1 : 0)];
            int n = NativeApi.llama_tokenize(ctx, text, res, res.Length, add_bos);
            if (n < 0)
            {
                throw new RuntimeError("Error happened during tokenization. It's possibly caused by wrong encoding. Please try to " +
                    "specify the encoding.");
            }
            return res.Take(n).ToList();
        }

        public static void llama_sample_top_k(SafeLLamaContextHandle ctx, LLamaTokenDataArray candidates, int k, ulong min_keep)
        {
            var handle = candidates.data.Pin();
            var st = new LLamaTokenDataArrayNative();
            st.data = new IntPtr(handle.Pointer);
            st.size = candidates.size;
            st.sorted = candidates.sorted;
            NativeApi.llama_sample_top_k(ctx, new IntPtr(&st), k, min_keep);
        }

        public static void llama_sample_top_p(SafeLLamaContextHandle ctx, LLamaTokenDataArray candidates, float p, ulong min_keep)
        {
            var handle = candidates.data.Pin();
            var st = new LLamaTokenDataArrayNative();
            st.data = new IntPtr(handle.Pointer);
            st.size = candidates.size;
            st.sorted = candidates.sorted;
            NativeApi.llama_sample_top_p(ctx, new IntPtr(&st), p, min_keep);
        }
        public static void llama_sample_temperature(SafeLLamaContextHandle ctx, LLamaTokenDataArray candidates, float temp)
        {
            var handle = candidates.data.Pin();
            var st = new LLamaTokenDataArrayNative();
            st.data = new IntPtr(handle.Pointer);
            st.size = candidates.size;
            st.sorted = candidates.sorted;
            NativeApi.llama_sample_temperature(ctx, new IntPtr(&st), temp);
        }

        public static llama_token llama_sample_token(SafeLLamaContextHandle ctx, LLamaTokenDataArray candidates)
        {
            var handle = candidates.data.Pin();
            var st = new LLamaTokenDataArrayNative();
            st.data = new IntPtr(handle.Pointer);
            st.size = candidates.size;
            st.sorted = candidates.sorted;
            return NativeApi.llama_sample_token(ctx, new IntPtr(&st));
        }
    }
}