#!/usr/bin/env python3
"""Auto-categorize verified status page entries based on service name keywords.

Run: python3 scripts/auto-categorize.py scripts/new-verified.json
"""

import json
import sys
import re

# Keyword-to-category mappings (checked in order, first match wins)
RULES = [
    # AI & ML
    (r"\b(ai|ml|llm|gpt|claude|anthropic|openai|cohere|replicate|pinecone|hugging|mistral|groq|elevenlabs|stability|cursor|together)\b", "AI & ML"),

    # Gaming
    (r"\b(game|gaming|steam|epic|riot|roblox|xbox|playstation|nintendo|unity|unreal|fortnite|valorant|geforce|nvidia)\b", "Gaming"),

    # Education
    (r"\b(edu|school|university|college|learn|course|canvas|clever|classlink|instructure|coursera|udemy|flocabulary|blackboard|brightspace|schoology)\b", "Education"),

    # Finance / Payments
    (r"\b(pay|payment|stripe|square|brex|chargebee|gocardless|adyen|checkout|merchant|billing|invoice|fintech|banking|coinbase|crypto|wallet|bitcoin|ethereum|plaid)\b", "Payments"),
    (r"\b(accounting|quickbooks|xero|gusto|rippling|payroll|tax)\b", "Finance"),

    # Healthcare
    (r"\b(health|medical|clinic|patient|hipaa|ehr|pharmacy|dental)\b", "Healthcare"),

    # E-commerce
    (r"\b(shop|commerce|ecommerce|store|retail|cart|woo|magento|bigcommerce|squarespace|wix|gumroad|etsy)\b", "E-commerce"),

    # Security & Identity
    (r"\b(security|auth|identity|sso|mfa|password|1password|lastpass|okta|auth0|crowdstrike|snyk|vanta|tailscale|jumpcloud|duo|clerk|stytch|workos|veriff|persona|bitwarden|cert|ssl|vpn|firewall|waf)\b", "Security"),

    # Communication
    (r"\b(slack|discord|message|messaging|chat|sms|voice|email|mail|twilio|sendgrid|mailgun|intercom|zendesk|freshdesk|helpscout|vonage|pusher|stream|bandwidth|telnyx|brevo|postmark|mailchimp)\b", "Communication"),

    # CRM
    (r"\b(crm|salesforce|hubspot|front)\b", "CRM"),

    # HR
    (r"\b(hr|human.resource|bamboo|lattice|deel|workday|rippling|recruiting|talent)\b", "HR"),

    # Monitoring & Observability
    (r"\b(monitor|observ|alert|pager|opsgenie|datadog|newrelic|grafana|sentry|amplitude|mixpanel|honeycomb|logrocket|lightstep|apm|logging|incident|uptime|pingdom)\b", "Monitoring"),

    # Analytics
    (r"\b(analytics|analytic|heap|fullstory|pendo|hotjar|segment|posthog|amplitude|mixpanel|tracking)\b", "Analytics"),

    # Databases
    (r"\b(database|db|sql|mongo|postgres|mysql|redis|elastic|supabase|cockroach|planetscale|fauna|snowflake|confluent|upstash|hasura|fivetran|dbt|neon|data.warehouse|bigquery)\b", "Databases"),

    # Cloud & Hosting
    (r"\b(cloud|hosting|cdn|server|aws|azure|gcp|vercel|netlify|heroku|railway|render|digitalocean|linode|fly\.io|cloudflare|fastly|akamai|bunny|dns|domain|godaddy|namecheap)\b", "Cloud & Hosting"),

    # CMS
    (r"\b(cms|contentful|sanity|prismic|hygraph|wordpress|ghost|storyblok|strapi)\b", "CMS"),

    # Developer Tools
    (r"\b(dev|developer|api|sdk|ci|cd|build|deploy|github|gitlab|bitbucket|circleci|jenkins|docker|terraform|pulumi|npm|deno|code|ide|jetbrains|postman|expo|cypress|buildkite|linear|jira|confluence|trello|sentry|launchdarkly|hashicorp|retool|appsmith|mapbox|algolia|twilio.segment)\b", "Developer Tools"),

    # Media
    (r"\b(media|video|image|photo|stream|cdn|cloudinary|imgix|mux|vimeo|flickr|unsplash|giphy|imgur|youtube|loom|wetransfer)\b", "Media"),

    # Social & Media
    (r"\b(social|reddit|twitter|facebook|instagram|linkedin|pinterest|tumblr|medium|tiktok|snapchat|bluesky|mastodon|spotify|twitch|patreon|kickstarter|opensea|disqus|trustpilot|yelp)\b", "Social & Media"),

    # Productivity
    (r"\b(project|task|calendar|schedule|document|doc|note|notion|asana|monday|airtable|zapier|box|dropbox|zoom|figma|miro|webflow|canva|clickup|coda|smartsheet|docusign|typeform|jotform|grammarly|loom|calendly|buffer|bitly|constant.contact|survey)\b", "Productivity"),

    # IoT
    (r"\b(iot|sensor|device|samsara|particle)\b", "IoT"),

    # Atlassian
    (r"\.status\.atlassian\.com", "Atlassian"),
]


def categorize(name, url):
    text = f"{name} {url}".lower()
    for pattern, category in RULES:
        if re.search(pattern, text, re.IGNORECASE):
            return category
    return "Uncategorized"


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 scripts/auto-categorize.py <input.json> [output.json]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else input_path

    with open(input_path) as f:
        entries = json.load(f)

    categorized = 0
    still_unknown = 0
    cats = {}

    for entry in entries:
        if entry.get("category", "Uncategorized") == "Uncategorized":
            cat = categorize(entry["name"], entry["base_url"])
            entry["category"] = cat
            if cat != "Uncategorized":
                categorized += 1
            else:
                still_unknown += 1
        cats[entry["category"]] = cats.get(entry["category"], 0) + 1

    with open(output_path, "w") as f:
        json.dump(entries, f, indent=2, ensure_ascii=False)

    print(f"Categorized: {categorized}")
    print(f"Still uncategorized: {still_unknown}")
    print(f"\nBy category:")
    for k, v in sorted(cats.items(), key=lambda x: -x[1]):
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
