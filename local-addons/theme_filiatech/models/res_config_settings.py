from odoo import fields, models


class ResConfigSettings(models.TransientModel):
    _inherit = "res.config.settings"

    theme_filiatech_accent_primary = fields.Char(
        string="FiliaTech primary accent",
        default="#17e3c0",
        config_parameter="theme_filiatech.accent_primary",
        help="Primary neon accent color used across the theme.",
    )
    theme_filiatech_accent_secondary = fields.Char(
        string="FiliaTech secondary accent",
        default="#6c63ff",
        config_parameter="theme_filiatech.accent_secondary",
        help="Secondary accent color for gradients and outlines.",
    )
    theme_filiatech_show_cases = fields.Boolean(
        string="Show case studies section",
        default=True,
        config_parameter="theme_filiatech.show_cases",
        help="Toggle the case study block on the homepage.",
    )
    theme_filiatech_show_blog = fields.Boolean(
        string="Show blog highlights",
        default=True,
        config_parameter="theme_filiatech.show_blog",
        help="Toggle the blog highlights section on the homepage.",
    )
