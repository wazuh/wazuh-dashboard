# Selects the versions of a dashboard package builder image to delete from ghcr.
#
# Input: the versions of one container package, as returned by
#   GET /orgs/{org}/packages/container/{name}/versions (all pages merged).
# Output (with jq -r): one "<id>\t<reason>" line per version to delete.
#
# Builder image tags are <version>-<12 hex chars of the Dockerfile sha256>
# (see builder-image.sh). A version is deleted when:
# - it has no tags, or
# - every tag has that format and none of them is the newest one (by the
#   version's created_at) for its prefix, the part before the last "-".
# A version with any tag in another format is never deleted.
#
# This keeps the current image of every version branch, whatever the number of
# branches. Tests: test-builder-image-retention.sh.

def parse: capture("^(?<prefix>.+)-(?<hash>[0-9a-f]{12})$");

. as $all
# The id of the newest version of each prefix.
| [ $all[] | .created_at as $created_at | .id as $id
    | (.metadata.container.tags // [])[] | select(test("^.+-[0-9a-f]{12}$"))
    | parse + {id: $id, created_at: $created_at} ]
| group_by(.prefix) | map(max_by(.created_at)) | map(.id) as $current
| $all[]
| (.metadata.container.tags // []) as $tags
| if ($tags | length) == 0 then "\(.id)\tuntagged"
  elif any($tags[]; test("^.+-[0-9a-f]{12}$") | not) then empty
  elif ([.id] | inside($current)) then empty
  else "\(.id)\tsuperseded: \($tags | join(","))" end
