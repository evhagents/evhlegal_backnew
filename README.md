# EVH Legal Chat

A Phoenix LiveView application for legal document analysis and chat assistance, powered by OpenRouter AI.

## Features

- **Legal Document Analysis**: Upload and analyze NDAs, joinders, and other legal documents
- **AI-Powered Chat**: Ask questions about legal terms, notice periods, governing law, and more
- **Modern UI**: Built with Phoenix LiveView and Tailwind CSS
- **Real-time Updates**: Live chat interface with streaming responses

## Setup

### Prerequisites

- Elixir 1.15+ and Erlang/OTP 26+
- PostgreSQL 12+
- Node.js 18+ (for assets)

### Installation

1. **Clone and install dependencies:**
   ```bash
   git clone <repository-url>
   cd evhlegalchat
   mix setup
   ```

2. **Set up environment variables:**
   
   Create a `.env` file in the project root:
   ```bash
   OPENROUTER_API_KEY=your_openrouter_api_key_here
   ```

   Or set the environment variable directly:
   ```bash
   # Windows PowerShell
   $env:OPENROUTER_API_KEY="your_api_key_here"
   
   # Linux/macOS
   export OPENROUTER_API_KEY="your_api_key_here"
   ```

3. **Start the development server:**
   ```bash
   mix phx.server
   ```

4. **Visit the application:**
   Open [http://localhost:4000](http://localhost:4000) in your browser.

## Configuration

### OpenRouter API

The application uses OpenRouter for AI chat functionality. You'll need to:

1. Sign up at [OpenRouter](https://openrouter.ai/)
2. Get your API key
3. Set the `OPENROUTER_API_KEY` environment variable

### Database

The application uses PostgreSQL. Make sure PostgreSQL is running and accessible with the credentials in `config/dev.exs`.

## Development

### Running Tests

```bash
mix test
```

### Code Quality

```bash
mix precommit  # Runs compile, format, and tests
```

### Environment Variables

- `OPENROUTER_API_KEY`: Your OpenRouter API key (required)
- `PORT`: Server port (default: 4000)
- `PHX_HOST`: Host for the Phoenix server (default: localhost)

## Production Deployment

For production deployment:

1. Set the `OPENROUTER_API_KEY` environment variable
2. Configure your database URL
3. Set `SECRET_KEY_BASE` for session encryption
4. Use `mix phx.gen.release` to generate a release

See [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html) for more details.

## Learn More

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
- [OpenRouter API](https://openrouter.ai/docs)
