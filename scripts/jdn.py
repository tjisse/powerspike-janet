"""Small data-only JDN writer for the Python transport tools; no Janet evaluation."""
import math
import re


def dumps(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        if not math.isfinite(value):
            raise ValueError("non-finite values are not observation data")
        return repr(value)
    if isinstance(value, str):
        encoded = []
        for char in value:
            if char in ('"', '\\'):
                encoded.append('\\' + char)
            elif ord(char) < 32:
                encoded.append('\\x%02x' % ord(char))
            else:
                encoded.append(char)
        return '"' + ''.join(encoded) + '"'
    if isinstance(value, (list, tuple)):
        return '[' + ' '.join(dumps(v) for v in value) + ']'
    if isinstance(value, dict):
        fields = []
        for key, item in value.items():
            if not isinstance(key, str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9-]*', key):
                raise ValueError("unsupported JDN keyword key: %r" % key)
            fields.append(':' + key + ' ' + dumps(item))
        return '{' + '\n '.join(fields) + '}'
    raise ValueError("unsupported observation value: %r" % type(value))
