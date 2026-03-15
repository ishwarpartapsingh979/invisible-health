"""
MCP Client Manager
Handles connections to Swiggy Instamart, Zepto, and Zomato MCP servers.
"""
import os
import json
import httpx
from typing import Dict, List, Any, Optional
from datetime import datetime, timedelta


class MCPClient:
    """
    Client for interacting with Model Context Protocol (MCP) servers.
    Supports multiple food delivery and grocery services.
    """

    def __init__(self, config_path: str = "mcp_config.json"):
        """Initialize MCP client with configuration."""
        # Load configuration
        with open(config_path, 'r') as f:
            self.config = json.load(f)

        self.servers = self.config['servers']
        self.timeout = self.config.get('timeout_seconds', 30)
        self.retry_attempts = self.config.get('retry_attempts', 3)

        # Auth tokens storage (in production, use secure storage)
        self.auth_tokens: Dict[str, str] = {}
        self._load_auth_tokens()

        # HTTP client
        self.client = httpx.Client(timeout=self.timeout)

    def _load_auth_tokens(self):
        """Load authentication tokens from environment variables."""
        # Expected env vars: SWIGGY_AUTH_TOKEN, ZEPTO_AUTH_TOKEN, ZOMATO_API_KEY
        self.auth_tokens = {
            'swiggy_instamart': os.getenv('SWIGGY_AUTH_TOKEN', ''),
            'swiggy_food': os.getenv('SWIGGY_AUTH_TOKEN', ''),
            'swiggy_dineout': os.getenv('SWIGGY_AUTH_TOKEN', ''),
            'zepto': os.getenv('ZEPTO_AUTH_TOKEN', ''),
            'zomato': os.getenv('ZOMATO_API_KEY', '')
        }

    def _get_headers(self, service: str) -> Dict[str, str]:
        """Get HTTP headers for MCP request including authentication."""
        headers = {
            'Content-Type': 'application/json',
            'User-Agent': 'InvisibleHealth-NutritionAgent/1.0'
        }

        # Add authentication based on service type
        server_config = self.servers.get(service, {})
        auth_type = server_config.get('auth_type', 'none')

        if auth_type == 'oauth' and self.auth_tokens.get(service):
            headers['Authorization'] = f'Bearer {self.auth_tokens[service]}'
        elif auth_type == 'api_key' and self.auth_tokens.get(service):
            headers['X-API-Key'] = self.auth_tokens[service]
        elif auth_type == 'pkce':
            # PKCE tokens are handled differently (OAuth 2.1)
            if self.auth_tokens.get(service):
                headers['Authorization'] = f'Bearer {self.auth_tokens[service]}'

        return headers

    def call_tool(self, service: str, tool_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """
        Call a specific tool on an MCP server.

        Args:
            service: Service name (e.g., 'swiggy_instamart', 'zepto', 'zomato')
            tool_name: Name of the tool to call (e.g., 'search_groceries')
            arguments: Tool arguments as dictionary

        Returns:
            Tool response as dictionary
        """
        if service not in self.servers:
            raise ValueError(f"Unknown service: {service}")

        server_url = self.servers[service]['url']
        headers = self._get_headers(service)

        # MCP tool call payload
        payload = {
            "jsonrpc": "2.0",
            "id": f"{service}_{tool_name}_{datetime.now().timestamp()}",
            "method": "tools/call",
            "params": {
                "name": tool_name,
                "arguments": arguments
            }
        }

        # Make request with retry logic
        for attempt in range(self.retry_attempts):
            try:
                response = self.client.post(server_url, json=payload, headers=headers)
                response.raise_for_status()

                result = response.json()

                # Check for MCP errors
                if 'error' in result:
                    error_msg = result['error'].get('message', 'Unknown error')
                    print(f"❌ MCP Error from {service}: {error_msg}")
                    return {'error': error_msg, 'service': service}

                # Return successful result
                return result.get('result', {})

            except httpx.HTTPStatusError as e:
                print(f"⚠️ HTTP error on attempt {attempt + 1}/{self.retry_attempts}: {e}")
                if attempt == self.retry_attempts - 1:
                    return {
                        'error': f'HTTP {e.response.status_code}: {str(e)}',
                        'service': service
                    }
            except Exception as e:
                print(f"⚠️ Error on attempt {attempt + 1}/{self.retry_attempts}: {str(e)}")
                if attempt == self.retry_attempts - 1:
                    return {'error': str(e), 'service': service}

        return {'error': 'Max retries exceeded', 'service': service}

    def list_tools(self, service: str) -> List[Dict[str, Any]]:
        """
        List available tools for a service.

        Args:
            service: Service name

        Returns:
            List of available tools
        """
        if service not in self.servers:
            raise ValueError(f"Unknown service: {service}")

        server_url = self.servers[service]['url']
        headers = self._get_headers(service)

        payload = {
            "jsonrpc": "2.0",
            "id": f"{service}_list_tools",
            "method": "tools/list"
        }

        try:
            response = self.client.post(server_url, json=payload, headers=headers)
            response.raise_for_status()
            result = response.json()

            return result.get('result', {}).get('tools', [])
        except Exception as e:
            print(f"❌ Error listing tools for {service}: {str(e)}")
            return []

    def close(self):
        """Close HTTP client."""
        self.client.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()


# Singleton instance for reuse across function calls
_mcp_client_instance: Optional[MCPClient] = None


def get_mcp_client() -> MCPClient:
    """Get or create singleton MCP client instance."""
    global _mcp_client_instance

    if _mcp_client_instance is None:
        config_path = os.path.join(os.path.dirname(__file__), 'mcp_config.json')
        _mcp_client_instance = MCPClient(config_path)

    return _mcp_client_instance
