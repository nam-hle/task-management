package crossref

import "regexp"

// jiraKeyPattern matches Jira issue keys (e.g., PROJ-123, ABC-1).
var jiraKeyPattern = regexp.MustCompile(`([A-Z][A-Z0-9]+-\d+)`)

// ExtractJiraKeys extracts all Jira issue key matches from text.
// Returns a deduplicated list preserving the order of first occurrence.
func ExtractJiraKeys(text string) []string {
	matches := jiraKeyPattern.FindAllString(text, -1)
	if len(matches) == 0 {
		return nil
	}

	seen := make(map[string]bool)
	var result []string
	for _, m := range matches {
		if seen[m] {
			continue
		}
		seen[m] = true
		result = append(result, m)
	}
	return result
}

// MatchCrossRefs extracts Jira issue keys from a PR's branch name,
// title, and description. If jiraTaskIDs is non-nil, only keys that
// appear in that set are returned; otherwise all found keys are returned.
func MatchCrossRefs(
	prBranch string,
	prTitle string,
	prDescription string,
	jiraTaskIDs map[string]bool,
) []string {
	combined := prBranch + " " + prTitle + " " + prDescription
	keys := ExtractJiraKeys(combined)

	if jiraTaskIDs == nil || len(jiraTaskIDs) == 0 {
		return keys
	}

	var filtered []string
	for _, key := range keys {
		if jiraTaskIDs[key] {
			filtered = append(filtered, key)
		}
	}
	return filtered
}
