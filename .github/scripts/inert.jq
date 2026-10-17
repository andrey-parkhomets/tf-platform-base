# Makes model-written text inert before it is posted to a pull request. The text may have been steered by an injected diff or review
# comment, so it is treated as hostile: it must not render as a link, an image, HTML, a mention, a cross-reference, or as a section
# of the bot's own comment. Used by clean-report.sh and sanitize-text.sh; tested by scripts/test-guards.sh.
#
# This file is ASCII only on purpose: every special character is written as a backslash-u escape, so nothing invisible hides in the
# source (a test checks it).
#
# What it does, in this order:
#   - control characters, newlines and tabs become one space (a field is one line, so it cannot forge a heading, a table row,
#     a fence or a "Committed to this branch" line of its own)
#   - zero-width and bidirectional controls are removed (they hide or reorder text)
#   - < and > become single angle quotes U+2039/U+203A (no HTML, no comments, no marker spoofing); @ gets a zero-width space U+200B
#     (no mentions)
#   - "](" becomes "] (" (no inline link or image), "://" and "www." are broken (no autolink), "#<digit>" is broken (no cross-reference)
#   - three backticks become three apostrophes (no fence)
def inert:
  gsub("[\u0001-\u001f\u007f\u0085\u2028\u2029]+"; " ")
  | gsub("[\u200b-\u200f\u202a-\u202e\u2060-\u2069\ufeff]"; "")
  | gsub("<"; "\u2039") | gsub(">"; "\u203a")
  | gsub("@"; "@\u200b")
  | gsub("\\]\\("; "] (")
  | gsub("://"; ":/\u200b/")
  | gsub("(?<w>[Ww][Ww][Ww])\\."; "\(.w)\u200b.")
  | gsub("#(?<d>[0-9])"; "#\u200b\(.d)")
  | gsub("```"; "'''");

# bounded length, in characters, with an ellipsis (U+2026) when cut
def inert($n): inert | if length > $n then .[0:$n] + "\u2026" else . end;

# values with a known shape are validated, not just escaped
def ident($n): if type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._/-]{0,\($n)}$") and (contains("..") | not) then . else empty end;
def slugword($n): if type == "string" and test("^[A-Za-z0-9_-]{1,\($n)}$") then . else empty end;
def skillname: if type == "string" and test("^[a-z0-9-]{1,40}$") then . else empty end;
def oneof($allowed; $fallback): if . as $v | $allowed | index($v) then . else $fallback end;
