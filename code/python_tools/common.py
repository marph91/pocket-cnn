"""Module for common functionalities."""


class CnnArchitectureError(Exception):
    """Raised when something is wrong with the CNN architecture."""


class InconsistencyError(Exception):
    """Raised when metainformations don't fit."""


class NotSupportedError(Exception):
    """Raised when a parameter is not supported."""
