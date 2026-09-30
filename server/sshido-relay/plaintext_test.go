package main

import "testing"

func TestPlainText(t *testing.T) {
	cases := []struct{ in, want string }{
		{"**Done.** Tests pass.", "Done. Tests pass."},
		{"Edited `main.go` and __two__ files", "Edited main.go and two files"},
		{"*emphasis* and _also_ this", "emphasis and also this"},
		{"keep snake_case_names and 2*3*4", "keep snake_case_names and 2*3*4"},
		{"See [the PR](https://github.com/x/y/pull/1) and ![shot](a.png)", "See the PR and shot"},
		{"## Summary\n\n- one\n- two\n* [x] done", "Summary\n\none\ntwo\ndone"},
		{"> quoted line\nnext", "quoted line\nnext"},
		{"```go\nfunc a() {}\n```", "func a() {}"},
		{"| Check | Result |\n|---|---|\n| TLS | pass |", "Check · Result\nTLS · pass"},
		{"~~old~~ new", "old new"},
		{"above\n\n---\n\nbelow", "above\n\nbelow"},
		{`literal \*star\* and 1\. item`, "literal *star* and 1. item"},
		{"1. first\n2. second", "1. first\n2. second"},
		{"<https://sshido.com>", "https://sshido.com"},
		{"한국어 **굵게** 텍스트", "한국어 굵게 텍스트"},
		{"", ""},
	}
	for _, c := range cases {
		if got := plainText(c.in); got != c.want {
			t.Errorf("plainText(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
