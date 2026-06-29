# Aliyun ESA PAGES frontend artifact notes

## Files
- default/: static build output from web/default
- classic/: static build output from web/classic

## Deployment suggestions
- Deploy to Aliyun ESA PAGES or another static hosting platform
- If frontend and backend use different domains, verify the frontend API base URL strategy
- To set a backend URL for the classic frontend, pass -FrontendServerUrl https://api.example.com

## Current project limits
- The default frontend mainly calls the backend through same-origin /api, so it works best with:
  - reverse proxy on the same domain
  - a gateway in front of ESA PAGES that forwards /api, /mj, and /pg to the backend
- The classic frontend supports a custom backend URL through VITE_REACT_APP_SERVER_URL
