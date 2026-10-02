package main

import (
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
)

func TestLandingLinksTheLiveAppStoreListing(t *testing.T) {
	s := newTestServer(t)
	w := httptest.NewRecorder()
	s.landing(w, httptest.NewRequest(http.MethodGet, "/", nil))
	body := w.Body.String()
	if w.Code != http.StatusOK {
		t.Fatalf("status %d", w.Code)
	}
	if strings.Contains(body, "id6746527541") || strings.Count(body, "https://apps.apple.com/app/sshido/id6762311864") != 2 {
		t.Fatal("both download buttons must point at the live listing id6762311864")
	}
	if strings.Contains(body, "{{") {
		t.Fatal("unreplaced placeholder in the landing page")
	}
	if strings.Contains(body, "No analytics") || strings.Contains(body, "All data on-device") {
		t.Fatal("the landing page must not claim no analytics while crash reports are on by default")
	}
}

func TestLandingImagesAreServed(t *testing.T) {
	s := newTestServer(t)
	w := httptest.NewRecorder()
	s.landing(w, httptest.NewRequest(http.MethodGet, "/", nil))
	images := regexp.MustCompile(`src="(/site/[a-z]+\.jpg)"`).FindAllStringSubmatch(w.Body.String(), -1)
	if len(images) != 5 {
		t.Fatalf("expected 5 screenshots, found %d", len(images))
	}
	for _, m := range images {
		rec := httptest.NewRecorder()
		s.siteAsset().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, m[1], nil))
		if rec.Code != http.StatusOK || rec.Header().Get("Content-Type") != "image/jpeg" || rec.Body.Len() < 10_000 {
			t.Fatalf("%s: status %d type %q size %d", m[1], rec.Code, rec.Header().Get("Content-Type"), rec.Body.Len())
		}
	}
}
