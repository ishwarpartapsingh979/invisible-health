"""
Grocery & Food Delivery Tools
High-level wrapper functions for MCP services (Swiggy, Zepto, Zomato).
"""
from typing import Dict, List, Any, Optional
from mcp_client import get_mcp_client


class GroceryTools:
    """
    Provides high-level grocery and food ordering capabilities via MCP.
    """

    def __init__(self):
        self.mcp = get_mcp_client()

    # ==================== SEARCH & DISCOVERY ====================

    def search_groceries(self, query: str, service: str = 'swiggy_instamart',
                        limit: int = 10) -> List[Dict[str, Any]]:
        """
        Search for grocery items across services.

        Args:
            query: Search query (e.g., "chicken breast", "brown rice")
            service: Which service to search ('swiggy_instamart', 'zepto')
            limit: Max number of results

        Returns:
            List of products with name, price, nutrition info
        """
        result = self.mcp.call_tool(
            service=service,
            tool_name='search_items',
            arguments={'query': query, 'limit': limit}
        )

        if 'error' in result:
            print(f"❌ Search error: {result['error']}")
            return []

        # Parse and standardize results
        items = result.get('items', [])
        return self._standardize_items(items, service)

    def search_all_services(self, query: str) -> Dict[str, List[Dict[str, Any]]]:
        """
        Search across ALL available grocery services and compare.

        Args:
            query: Search query

        Returns:
            Dictionary with service names as keys and results as values
        """
        services = ['swiggy_instamart', 'zepto']
        results = {}

        for service in services:
            try:
                results[service] = self.search_groceries(query, service=service)
            except Exception as e:
                print(f"⚠️ Failed to search {service}: {str(e)}")
                results[service] = []

        return results

    def compare_prices(self, query: str) -> List[Dict[str, Any]]:
        """
        Compare prices of an item across all services.

        Args:
            query: Item to search for

        Returns:
            List of items sorted by price (cheapest first)
        """
        all_results = self.search_all_services(query)

        # Flatten all results
        all_items = []
        for service, items in all_results.items():
            for item in items:
                item['service'] = service
                all_items.append(item)

        # Sort by price
        all_items.sort(key=lambda x: x.get('price', float('inf')))

        return all_items

    # ==================== NUTRITION & DETAILS ====================

    def get_nutrition_info(self, item_id: str, service: str) -> Optional[Dict[str, Any]]:
        """
        Get detailed nutrition information for an item.

        Args:
            item_id: Product ID
            service: Service name

        Returns:
            Nutrition facts (calories, protein, carbs, fats)
        """
        result = self.mcp.call_tool(
            service=service,
            tool_name='get_nutrition',
            arguments={'item_id': item_id}
        )

        if 'error' in result:
            print(f"❌ Nutrition fetch error: {result['error']}")
            return None

        return result.get('nutrition', {})

    # ==================== RESTAURANT DISCOVERY (Zomato/Swiggy Food) ====================

    def search_restaurants(self, location: Optional[Dict[str, float]] = None,
                          cuisine: Optional[str] = None,
                          service: str = 'zomato') -> List[Dict[str, Any]]:
        """
        Search for restaurants.

        Args:
            location: {'lat': 12.9716, 'lng': 77.5946}
            cuisine: Filter by cuisine type
            service: 'zomato' or 'swiggy_food'

        Returns:
            List of restaurants
        """
        arguments = {}
        if location:
            arguments['lat'] = location['lat']
            arguments['lng'] = location['lng']
        if cuisine:
            arguments['cuisine'] = cuisine

        result = self.mcp.call_tool(
            service=service,
            tool_name='search_restaurants',
            arguments=arguments
        )

        if 'error' in result:
            return []

        return result.get('restaurants', [])

    def get_menu(self, restaurant_id: str, service: str = 'zomato') -> List[Dict[str, Any]]:
        """
        Get menu for a restaurant.

        Args:
            restaurant_id: Restaurant ID
            service: Service name

        Returns:
            Menu items with prices and nutrition
        """
        result = self.mcp.call_tool(
            service=service,
            tool_name='get_menu',
            arguments={'restaurant_id': restaurant_id}
        )

        if 'error' in result:
            return []

        return result.get('menu', [])

    # ==================== CART MANAGEMENT ====================

    def add_to_cart(self, item_id: str, quantity: int = 1, service: str = 'swiggy_instamart') -> bool:
        """
        Add item to cart.

        Args:
            item_id: Product ID
            quantity: Quantity to add
            service: Service name

        Returns:
            True if successful
        """
        result = self.mcp.call_tool(
            service=service,
            tool_name='add_to_cart',
            arguments={'item_id': item_id, 'quantity': quantity}
        )

        if 'error' in result:
            print(f"❌ Add to cart failed: {result['error']}")
            return False

        return result.get('success', False)

    def view_cart(self, service: str = 'swiggy_instamart') -> Dict[str, Any]:
        """
        View current cart contents.

        Args:
            service: Service name

        Returns:
            Cart details with items and total
        """
        result = self.mcp.call_tool(
            service=service,
            tool_name='view_cart',
            arguments={}
        )

        if 'error' in result:
            return {'items': [], 'total': 0}

        return result.get('cart', {})

    # ==================== ORDER PLACEMENT ====================

    def place_order(self, service: str = 'swiggy_instamart',
                   delivery_address: Optional[str] = None) -> Dict[str, Any]:
        """
        Place an order with items currently in cart.

        Args:
            service: Service name
            delivery_address: Delivery address (optional if saved)

        Returns:
            Order details with order_id and tracking info
        """
        arguments = {}
        if delivery_address:
            arguments['delivery_address'] = delivery_address

        result = self.mcp.call_tool(
            service=service,
            tool_name='place_order',
            arguments=arguments
        )

        if 'error' in result:
            print(f"❌ Order placement failed: {result['error']}")
            return {'success': False, 'error': result['error']}

        return result

    def track_order(self, order_id: str, service: str) -> Dict[str, Any]:
        """
        Track order status.

        Args:
            order_id: Order ID
            service: Service name

        Returns:
            Order status and ETA
        """
        result = self.mcp.call_tool(
            service=service,
            tool_name='track_order',
            arguments={'order_id': order_id}
        )

        if 'error' in result:
            return {'status': 'unknown', 'error': result['error']}

        return result.get('order', {})

    # ==================== AI AGENT HELPERS ====================

    def suggest_protein_sources(self, budget: float = 500, goal_protein_g: float = 150) -> List[Dict[str, Any]]:
        """
        AI-powered: Find best protein sources within budget.

        Args:
            budget: Budget in INR
            goal_protein_g: Target protein in grams

        Returns:
            Suggested items optimized for protein/rupee ratio
        """
        # Search for common protein sources
        protein_keywords = [
            'chicken breast', 'paneer', 'eggs', 'greek yogurt',
            'moong dal', 'soya chunks', 'fish', 'tofu'
        ]

        all_options = []
        for keyword in protein_keywords:
            results = self.compare_prices(keyword)
            all_options.extend(results[:2])  # Top 2 from each

        # Calculate protein per rupee and sort
        for item in all_options:
            nutrition = item.get('nutrition', {})
            protein = nutrition.get('protein_g', 0)
            price = item.get('price', 1)

            item['protein_per_rupee'] = protein / price if price > 0 else 0

        # Sort by efficiency
        all_options.sort(key=lambda x: x['protein_per_rupee'], reverse=True)

        # Build combo within budget
        selected = []
        total_cost = 0
        total_protein = 0

        for item in all_options:
            if total_cost + item['price'] <= budget and total_protein < goal_protein_g:
                selected.append(item)
                total_cost += item['price']
                total_protein += item.get('nutrition', {}).get('protein_g', 0)

        return selected

    def smart_order_from_prompt(self, prompt: str, user_id: str) -> Dict[str, Any]:
        """
        AI-powered: Parse natural language and execute order.

        Example prompts:
        - "Order 500g chicken breast from cheapest source"
        - "Get me ingredients for high protein breakfast under ₹300"
        - "Order my post-workout meal"

        Args:
            prompt: Natural language request
            user_id: User ID for context

        Returns:
            Order summary
        """
        # This will be integrated with Gemini in agent_engine.py
        # For now, return structure
        return {
            'intent': 'parsed_from_prompt',
            'items': [],
            'service': 'auto_selected',
            'estimated_cost': 0,
            'estimated_nutrition': {}
        }

    # ==================== HELPER METHODS ====================

    def _standardize_items(self, items: List[Dict[str, Any]], service: str) -> List[Dict[str, Any]]:
        """
        Standardize item format across different MCP services.

        Args:
            items: Raw items from MCP
            service: Service name

        Returns:
            Standardized items
        """
        standardized = []

        for item in items:
            std_item = {
                'id': item.get('id') or item.get('product_id'),
                'name': item.get('name') or item.get('title'),
                'price': float(item.get('price', 0)),
                'service': service,
                'image_url': item.get('image_url'),
                'in_stock': item.get('in_stock', True),
                'nutrition': {
                    'calories': item.get('calories', 0),
                    'protein_g': item.get('protein', 0),
                    'carbs_g': item.get('carbs', 0),
                    'fats_g': item.get('fats', 0)
                }
            }
            standardized.append(std_item)

        return standardized
