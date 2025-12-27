import functions_framework

@functions_framework.http
def analyze_log(request):
    """HTTP Cloud Function.
    Args:
        request (flask.Request): The request object.
    Returns:
        The response text, or any set of values that can be turned into a
        Response object using `make_response`.
    """
    return 'Hello World! The deployment worked.', 200
