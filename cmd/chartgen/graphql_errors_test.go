package main

import (
	"encoding/json"
	"strings"
	"testing"
)

// A page where one definition's ingestionSourcesConfig failed to resolve, as
// the API returns it when that definition's stored config is not valid JSON.
const brokenSourcesPage = `{
  "data": {"integrationDefinitions": {
    "definitions": [
      {"name": "good", "integrationPlatformFeatures": {"supportsCollectors": true}, "ingestionSourcesConfig": []},
      {"name": "broken", "integrationPlatformFeatures": {"supportsCollectors": true}, "ingestionSourcesConfig": null}
    ],
    "pageInfo": {"hasNextPage": false}
  }},
  "errors": [{
    "message": "Unexpected end of JSON input",
    "path": ["integrationDefinitions", "definitions", 1, "ingestionSourcesConfig"]
  }]
}`

func decodePage(t *testing.T, body string) GraphQLResponse {
	t.Helper()
	var resp GraphQLResponse
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestUsableDefinitions_SkipsDefinitionWithBrokenSources(t *testing.T) {
	defs, err := usableDefinitions(decodePage(t, brokenSourcesPage))
	if err != nil {
		t.Fatalf("want the page accepted, got %v", err)
	}
	if len(defs) != 1 || defs[0].Name != "good" {
		t.Fatalf("want only the good definition, got %+v", defs)
	}
}

func TestUsableDefinitions_FailsOnOtherErrors(t *testing.T) {
	page := strings.Replace(brokenSourcesPage, `"ingestionSourcesConfig"]`, `"configFields"]`, 1)
	if _, err := usableDefinitions(decodePage(t, page)); err == nil {
		t.Fatal("want an error for a failure outside ingestionSourcesConfig")
	}

	page = strings.Replace(brokenSourcesPage, `"path": ["integrationDefinitions", "definitions", 1, "ingestionSourcesConfig"]`, `"path": ["integrationDefinitions"]`, 1)
	if _, err := usableDefinitions(decodePage(t, page)); err == nil {
		t.Fatal("want an error for a failure of the whole list")
	}
}
