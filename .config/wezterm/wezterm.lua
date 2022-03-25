local wezterm = require 'wezterm';
return {
    color_scheme = "Chalk",
    font = wezterm.font("Rec Mono Duotone"),
    font_size = 12.0,
    hyperlink_rules = {
        -- Linkify things that look like URLs
        -- This is actually the default if you don't specify any hyperlink_rules
        {
          regex = "\\b\\w+://(?:[\\w.-]+)\\.[a-z]{2,15}\\S*\\b",
          format = "$0",
        },

        -- linkify email addresses
        {
          regex = "\\b\\w+@[\\w-]+(\\.[\\w-]+)+\\b",
          format = "mailto:$0",
        },

        -- file:// URI
        {
          regex = "\\bfile://\\S*\\b",
          format = "$0",
        },

        -- Make jira ticket numbers clickable GNAVS-2465
        {
          regex = "\\b([A-Z]+-\\d+)\\b",
          format = "https://bugs.indeed.com/browse/$1"
        }
    }
}
