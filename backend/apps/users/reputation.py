from .models import ReputationLog


REPUTATION_CHANGES = {
    'submitted': 10,
    'resolved': 20,
    'upvoted_5': 5,
    'invalid': -15,
    'fake': -30,
}


def get_reputation_level(score):
    """
    Return the reputation level based on the score.
    """

    if score <= 30:
        return 'low'

    if score <= 60:
        return 'normal'

    if score <= 80:
        return 'trusted'

    return 'highly_trusted'


def update_reputation(
    user,
    change,
    reason,
    related_issue=None
):
    """
    Update a user's reputation.

    The score is always kept between 0 and 100.
    A ReputationLog entry is created for every change.
    """

    # Calculate new score
    new_score = user.reputation_score + change

    # Clamp score to 0-100
    new_score = max(0, min(100, new_score))

    # Update user
    user.reputation_score = new_score
    user.reputation_level = get_reputation_level(new_score)

    user.save(
        update_fields=[
            'reputation_score',
            'reputation_level',
        ]
    )

    # Create reputation history record
    ReputationLog.objects.create(
        user=user,
        change=change,
        reason=reason,
        related_issue=related_issue,
    )

    return user