"""
Management command to backfill human-readable addresses for existing Issue records
that only contain latitude and longitude.

Usage:
    python manage.py backfill_addresses [--limit 50] [--force]
"""

import time
from django.core.management.base import BaseCommand
from apps.issues.models import Issue
from apps.issues.geocode import reverse_geocode, validate_coordinates


class Command(BaseCommand):
    help = "Backfill human-readable addresses for issues with missing address"

    def add_arguments(self, parser):
        parser.add_argument(
            "--limit",
            type=int,
            default=50,
            help="Maximum number of issues to process (default 50).",
        )
        parser.add_argument(
            "--force",
            action="store_true",
            help="Re-resolve issues that already have an address.",
        )
        parser.add_argument(
            "--delay",
            type=float,
            default=1.0,
            help="Delay in seconds between external requests to respect rate limits (default 1.0s).",
        )

    def handle(self, *args, **options):
        limit = options["limit"]
        force = options["force"]
        delay = options["delay"]

        queryset = Issue.objects.exclude(latitude__isnull=True).exclude(longitude__isnull=True)
        if not force:
            queryset = queryset.filter(address="")

        issues = list(queryset.order_by("-created_at")[:limit])
        total = len(issues)

        if total == 0:
            self.stdout.write(self.style.SUCCESS("No issues found requiring address backfill."))
            return

        self.stdout.write(f"Starting address backfill for {total} issue(s)...")

        updated_count = 0
        failed_count = 0

        for idx, issue in enumerate(issues, start=1):
            valid = validate_coordinates(issue.latitude, issue.longitude)
            if not valid:
                self.stdout.write(
                    self.style.WARNING(
                        f"[{idx}/{total}] Issue #{issue.id}: Invalid coordinates ({issue.latitude}, {issue.longitude}). Skipping."
                    )
                )
                failed_count += 1
                continue

            addr = reverse_geocode(issue.latitude, issue.longitude)
            if addr:
                issue.address = addr
                issue.save(update_fields=["address"])
                updated_count += 1
                self.stdout.write(
                    self.style.SUCCESS(f"[{idx}/{total}] Issue #{issue.id} -> '{addr}'")
                )
            else:
                failed_count += 1
                self.stdout.write(
                    self.style.NOTICE(f"[{idx}/{total}] Issue #{issue.id}: Address resolution failed/unavailable.")
                )

            # Polite delay between records
            if idx < total and delay > 0:
                time.sleep(delay)

        self.stdout.write(
            self.style.SUCCESS(
                f"Backfill finished: {updated_count} updated, {failed_count} unresolved out of {total} processed."
            )
        )
