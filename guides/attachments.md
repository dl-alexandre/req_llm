# Attachments & Multi-Modal Content

ReqLLM supports multi-modal content including images, PDFs, audio, and other file types. However, provider support varies significantly.

## Attachment Support by Provider

| Provider   | Images | PDFs | Audio | Video | Notes |
|------------|--------|------|-------|-------|-------|
| Anthropic  | ✅     | ✅   | ❌    | ❌    | Native PDF support via Documents API |
| Google     | ✅     | ✅   | ✅    | ✅    | Extensive multi-modal via Gemini |
| OpenAI     | ✅     | ❌   | ❌    | ❌    | Chat Completions API: images only |
| OpenRouter | ✅     | ✅*  | ✅*   | ✅*   | Depends on underlying model |
| xAI        | ✅     | ❌   | ❌    | ❌    | OpenAI-compatible: images only |
| Groq       | ✅     | ❌   | ❌    | ❌    | OpenAI-compatible: images only |
| Azure      | ✅     | ❌   | ❌    | ❌    | OpenAI-compatible: images only |

\* OpenRouter support depends on the underlying model being called.

## Using Attachments

### Images

All providers support image attachments:

```elixir
alias ReqLLM.Message.ContentPart

# From URL
context = ReqLLM.Context.new([
  ReqLLM.Context.user([
    ContentPart.text("What's in this image?"),
    ContentPart.image_url("https://example.com/image.jpg")
  ])
])

# From binary data
image_data = File.read!("photo.png")
context = ReqLLM.Context.new([
  ReqLLM.Context.user([
    ContentPart.text("Describe this image"),
    ContentPart.image(image_data, "image/png")
  ])
])

{:ok, response} = ReqLLM.generate_text("anthropic:claude-haiku-4-5", context)
```

### PDFs (Anthropic, Google, OpenRouter)

```elixir
pdf_data = File.read!("document.pdf")

context = ReqLLM.Context.new([
  ReqLLM.Context.user([
    ContentPart.text("Summarize this document"),
    ContentPart.file(pdf_data, "document.pdf", "application/pdf")
  ])
])

# Works with Anthropic
{:ok, response} = ReqLLM.generate_text("anthropic:claude-sonnet-4", context)

# Works with Google
{:ok, response} = ReqLLM.generate_text("google:gemini-2.0-flash", context)

# Works with OpenRouter (model-dependent)
{:ok, response} = ReqLLM.generate_text("openrouter:anthropic/claude-3.5-sonnet", context)
```

### Audio (Google)

```elixir
audio_data = File.read!("recording.mp3")

context = ReqLLM.Context.new([
  ReqLLM.Context.user([
    ContentPart.text("Transcribe this audio"),
    ContentPart.file(audio_data, "recording.mp3", "audio/mpeg")
  ])
])

{:ok, response} = ReqLLM.generate_text("google:gemini-2.0-flash", context)
```

## Error Handling

When using unsupported attachment types, ReqLLM returns a clear error:

```elixir
pdf_data = File.read!("document.pdf")

context = ReqLLM.Context.new([
  ReqLLM.Context.user([
    ContentPart.text("Summarize this"),
    ContentPart.file(pdf_data, "doc.pdf", "application/pdf")
  ])
])

# Returns error for OpenAI
{:error, %ReqLLM.Error.Invalid.Capability{}} = 
  ReqLLM.generate_text("openai:gpt-4o", context)

# Error message explains the limitation and suggests alternatives
```

## Provider-Specific Notes

### Anthropic

Anthropic supports PDFs natively through their Documents API:
- Maximum 100 pages per document
- Maximum 32MB per document
- Supports PDF text extraction and image analysis

### Google (Gemini)

Google Gemini has the most extensive multi-modal support:
- Images: JPEG, PNG, GIF, WebP
- Audio: MP3, WAV, FLAC, OGG
- Video: MP4, MOV, WebM
- Documents: PDF, plain text

### OpenAI

OpenAI Chat Completions API only supports images:
- JPEG, PNG, GIF, WebP
- Maximum 20MB per image
- For document processing, consider using GPT-4o with extracted text

### OpenRouter

OpenRouter proxies to various providers, so attachment support depends on the underlying model:
- Anthropic models: Full Anthropic attachment support
- OpenAI models: Images only
- Google models: Full Google attachment support

## Choosing the Right Provider

For document-heavy workloads:
1. **Anthropic** - Best for PDF analysis with Claude models
2. **Google** - Best for mixed media (images, audio, video, documents)
3. **OpenRouter** - Good for flexibility, routing to the best model for the task

For image-only workloads:
- Any provider works well
- Consider cost and latency for your use case
