{
    "name": "FiliaTech Theme",
    "summary": "Dark, AI-inspired corporate theme for FiliaTech Odoo services",
    "version": "18.0.1.0.0",
    "category": "Theme/Corporate",
    "license": "LGPL-3",
    "author": "FiliaTech",
    "website": "https://filiatech.example.com",
    "depends": [
        "website",
        "website_blog",
        "website_form",
    ],
    "data": [
        "data/config_parameters.xml",
        "views/res_config_settings_views.xml",
        "views/layout_inherit.xml",
        "views/pages_templates.xml",
    ],
    "assets": {
        "web.assets_frontend": [
            "theme_filiatech/static/src/scss/theme.scss",
        ],
    },
}
