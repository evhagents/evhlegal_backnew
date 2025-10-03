# EVH Legal Chat - Reverse Proxy Setup

This Phoenix backend now acts as a reverse proxy to the React frontend at `https://evhlegal-front.onrender.com`.

## Architecture

- **Frontend Routes**: All routes (except `/api/*` and `/backend/*`) are proxied to the React frontend
- **API Routes**: `/api/*` routes are handled by the Phoenix backend with CORS enabled
- **Backend Routes**: `/backend/*` routes provide access to Phoenix LiveView pages
- **Development Routes**: `/dev/*` routes provide LiveDashboard and mailbox preview (dev only)

## Key Features

### 1. Reverse Proxy Controller
- Handles all HTTP methods (GET, POST, PUT, PATCH, DELETE)
- Forwards headers and query parameters
- Supports different content types (HTML, JSON, CSS, JS, images)
- Includes error handling and logging

### 2. CORS Configuration
- Enabled for API endpoints
- Allows requests from frontend domains
- Configurable origins and methods

### 3. Route Structure
```
/                    -> Proxied to React frontend
/users               -> Proxied to React frontend  
/dashboard           -> Proxied to React frontend
/api/*               -> Phoenix backend API
/backend/*           -> Phoenix LiveView pages
/dev/*               -> Development tools (dev only)
```

## Configuration

### Environment Variables
- `FRONTEND_URL`: URL of the React frontend (default: https://evhlegal-front.onrender.com)
- `PORT`: Port for the Phoenix server (default: 4000)
- `SECRET_KEY_BASE`: Secret key for Phoenix (required in production)

### CORS Origins
Configured to allow:
- `https://evhlegal-front.onrender.com` (production frontend)
- `http://localhost:3000` (local development)

## Development Setup

1. Install dependencies:
   ```bash
   mix deps.get
   ```

2. Set up the database:
   ```bash
   mix ecto.setup
   ```

3. Start the server:
   ```bash
   mix phx.server
   ```

4. Access the application:
   - Frontend: `http://localhost:4000/` (proxied to React app)
   - Backend: `http://localhost:4000/backend/` (Phoenix LiveView)
   - API: `http://localhost:4000/api/` (Phoenix API)
   - Dev tools: `http://localhost:4000/dev/` (development only)

## Production Deployment

1. Set environment variables:
   ```bash
   export SECRET_KEY_BASE="your-secret-key"
   export PORT=4000
   export PHX_SERVER=true
   ```

2. Build and start:
   ```bash
   mix assets.deploy
   PHX_SERVER=true mix phx.server
   ```

## API Integration

The backend can now serve API endpoints that the React frontend can consume:

```javascript
// Example API call from React frontend
fetch('/api/users', {
  method: 'GET',
  headers: {
    'Content-Type': 'application/json',
  },
})
.then(response => response.json())
.then(data => console.log(data));
```

## Monitoring

- Check proxy status via response headers:
  - `x-proxy-source`: "evhlegal-backend"
  - `x-proxy-status`: "success" or "error"
- Use LiveDashboard at `/dev/dashboard` for monitoring (development only)

## Troubleshooting

### Common Issues

1. **CORS Errors**: Ensure the frontend URL is in the CORS origins list
2. **Proxy Timeouts**: Check network connectivity to the frontend
3. **Content Type Issues**: Verify the proxy controller handles your content type

### Debug Mode

Enable debug logging by setting:
```elixir
config :logger, level: :debug
```

## Security Considerations

- The proxy forwards all headers - ensure sensitive headers are filtered if needed
- CORS is configured for specific origins - update for production
- Consider rate limiting for API endpoints
- Use HTTPS in production
