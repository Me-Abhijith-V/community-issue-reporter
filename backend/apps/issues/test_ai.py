from .ai_classifier import classify_issue


result = classify_issue(
    "There is a large pothole on the road near the bus stop."
)

print(result)