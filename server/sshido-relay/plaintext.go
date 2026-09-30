package main

import (
	"regexp"
	"strings"
)

var (
	mdFence       = regexp.MustCompile("(?m)^[ \\t]*(```|~~~).*$")
	mdImage       = regexp.MustCompile(`!\[([^\]]*)\]\([^)]*\)`)
	mdLink        = regexp.MustCompile(`\[([^\]]+)\]\([^)]*\)`)
	mdRefLink     = regexp.MustCompile(`\[([^\]]+)\]\[[^\]]*\]`)
	mdAutolink    = regexp.MustCompile(`<((?:https?|mailto):[^>\s]+)>`)
	mdHeading     = regexp.MustCompile(`(?m)^[ \t]{0,3}#{1,6}[ \t]+(.*?)[ \t]*#*[ \t]*$`)
	mdQuote       = regexp.MustCompile(`(?m)^[ \t]{0,3}>[ \t]?`)
	mdBullet      = regexp.MustCompile(`(?m)^([ \t]*)[-*+][ \t]+(\[[ xX]\][ \t]+)?`)
	mdRule        = regexp.MustCompile(`(?m)^[ \t]{0,3}([-*_])([ \t]*[-*_]){2,}[ \t]*$`)
	mdTableSep    = regexp.MustCompile(`(?m)^[ \t]*\|?[ \t]*:?-{2,}:?[ \t]*(\|[ \t]*:?-{2,}:?[ \t]*)*\|?[ \t]*\n?`)
	mdTableRow    = regexp.MustCompile(`(?m)^[ \t]*\|(.*)\|[ \t]*$`)
	mdBoldStars   = regexp.MustCompile(`\*\*(\S(?:.*?\S)?)\*\*`)
	mdBoldUnders  = regexp.MustCompile(`(^|[^\w])__(\S(?:.*?\S)?)__([^\w]|$)`)
	mdItalicStar  = regexp.MustCompile(`(^|[^\w*])\*(\S(?:.*?\S)?)\*([^\w*]|$)`)
	mdItalicUnder = regexp.MustCompile(`(^|[^\w])_(\S(?:.*?\S)?)_([^\w]|$)`)
	mdStrike      = regexp.MustCompile(`~~(\S(?:.*?\S)?)~~`)
	mdCode        = regexp.MustCompile("`+([^`]+?)`+")
	mdEscape      = regexp.MustCompile(`\\([\\` + "`" + `*_{}\[\]()#+\-.!|>~])`)
	blankRuns     = regexp.MustCompile(`\n{3,}`)
)

const escapeBase = 0xE000

func protectEscapes(s string) string {
	return mdEscape.ReplaceAllStringFunc(s, func(m string) string { return string(rune(escapeBase + int(m[1]))) })
}

func restoreEscapes(s string) string {
	return strings.Map(func(r rune) rune {
		if r > escapeBase && r < escapeBase+128 {
			return r - escapeBase
		}
		return r
	}, s)
}

func replace(re *regexp.Regexp, with string) func(string) string {
	return func(s string) string { return re.ReplaceAllString(s, with) }
}

var plainSteps = []func(string) string{
	protectEscapes,
	replace(mdFence, ""),
	replace(mdRule, ""),
	replace(mdTableSep, ""),
	func(s string) string { return mdTableRow.ReplaceAllStringFunc(s, tableRow) },
	replace(mdHeading, "$1"),
	replace(mdQuote, ""),
	replace(mdBullet, "$1"),
	replace(mdImage, "$1"),
	replace(mdLink, "$1"),
	replace(mdRefLink, "$1"),
	replace(mdAutolink, "$1"),
	replace(mdCode, "$1"),
	replace(mdBoldStars, "$1"),
	replace(mdBoldUnders, "$1$2$3"),
	replace(mdStrike, "$1"),
	replace(mdItalicStar, "$1$2$3"),
	replace(mdItalicUnder, "$1$2$3"),
	restoreEscapes,
	replace(blankRuns, "\n\n"),
	strings.TrimSpace,
}

func plainText(md string) string {
	out := strings.ReplaceAll(md, "\r\n", "\n")
	for _, step := range plainSteps {
		out = step(out)
	}
	return out
}

func tableRow(line string) string {
	cells := strings.Split(strings.Trim(strings.TrimSpace(line), "|"), "|")
	trimmed := make([]string, 0, len(cells))
	for _, c := range cells {
		trimmed = append(trimmed, strings.TrimSpace(c))
	}
	return strings.Join(trimmed, " · ")
}
