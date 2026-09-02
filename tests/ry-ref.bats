#!/usr/bin/env bats
# bin/ry-ref.sh and the URL helpers in bin/ry-forge-lib.sh. The remote shapes
# here are the ones the yard actually has, plus the scp form git also accepts.
load helpers

setup() { setup_home; . "$BATS_TEST_DIRNAME/../bin/ry-forge-lib.sh"; }

# Point a project's origin at a given URL. The clone was made from a local
# bare repo, so this is only ever read, never fetched.
set_remote() { git -C "$RY_HOME/projects/$1" remote set-url origin "$2"; }

@test "ry_web_base: ssh with port 22222, subgroup and .git" {
  run ry_web_base ssh://git@git.affinitybridge.com:22222/islandhealth/sub/public-site.git
  [ "$status" -eq 0 ]
  [ "$output" = https://git.affinitybridge.com/islandhealth/sub/public-site ]
}

@test "ry_web_base: ssh with port, no .git, keeps the whole group path" {
  run ry_web_base ssh://git@git.affinitybridge.com:22222/islandhealth/medical-staff
  [ "$output" = https://git.affinitybridge.com/islandhealth/medical-staff ]
}

@test "ry_web_base: ssh without a port" {
  run ry_web_base ssh://git@git.example.com/group/repo.git
  [ "$output" = https://git.example.com/group/repo ]
}

@test "ry_web_base: https with .git and a trailing slash" {
  run ry_web_base https://github.com/markdlabrecque/railyard.git/
  [ "$output" = https://github.com/markdlabrecque/railyard ]
}

@test "ry_web_base: https keeps its own port and drops user@" {
  run ry_web_base https://mark@gitlab.example.com:8443/group/repo.git
  [ "$output" = https://gitlab.example.com:8443/group/repo ]
}

@test "ry_web_base: scp-style git@host:owner/repo" {
  run ry_web_base git@github.com:markdlabrecque/railyard.git
  [ "$output" = https://github.com/markdlabrecque/railyard ]
}

@test "ry_web_base: scp-style with a subgroup" {
  run ry_web_base git@git.affinitybridge.com:affinitybridge/tools/affinity-client-registry.git
  [ "$output" = https://git.affinitybridge.com/affinitybridge/tools/affinity-client-registry ]
}

@test "ry_web_base: a local path is not a web URL" {
  run ry_web_base /srv/git/repo.git
  [ "$status" -ne 0 ]
  run ry_web_base file:///srv/git/repo.git
  [ "$status" -ne 0 ]
}

@test "ry_ticket_url / ry_pr_url: GitLab paths carry /-/" {
  run ry_ticket_url ssh://git@git.affinitybridge.com:22222/affinitybridge/affinity-client-registry.git 190
  [ "$output" = https://git.affinitybridge.com/affinitybridge/affinity-client-registry/-/issues/190 ]
  run ry_pr_url ssh://git@git.affinitybridge.com:22222/affinitybridge/affinity-client-registry.git 176
  [ "$output" = https://git.affinitybridge.com/affinitybridge/affinity-client-registry/-/merge_requests/176 ]
}

@test "ry_ticket_url / ry_pr_url: GitHub uses /issues and /pull" {
  run ry_ticket_url https://github.com/markdlabrecque/railyard.git 32
  [ "$output" = https://github.com/markdlabrecque/railyard/issues/32 ]
  run ry_pr_url https://github.com/markdlabrecque/railyard.git 31
  [ "$output" = https://github.com/markdlabrecque/railyard/pull/31 ]
}

@test "ry-ref.sh <project> #n: names the project and links the GitLab issue" {
  make_project island-health
  set_remote island-health ssh://git@git.affinitybridge.com:22222/islandhealth/public-site.git
  run bin/ry-ref.sh island-health '#27'
  [ "$status" -eq 0 ]
  [ "$output" = "island-health #27 https://git.affinitybridge.com/islandhealth/public-site/-/issues/27" ]
  run bin/ry-ref.sh island-health 27
  [ "$output" = "island-health #27 https://git.affinitybridge.com/islandhealth/public-site/-/issues/27" ]
}

@test "ry-ref.sh <project> !n: a merge request, and a GitHub pull" {
  make_project acr; make_project railyard
  set_remote acr ssh://git@git.affinitybridge.com:22222/affinitybridge/affinity-client-registry.git
  set_remote railyard https://github.com/markdlabrecque/railyard.git
  run bin/ry-ref.sh acr '!176'
  [ "$output" = "acr !176 https://git.affinitybridge.com/affinitybridge/affinity-client-registry/-/merge_requests/176" ]
  run bin/ry-ref.sh railyard '!30'
  [ "$output" = "railyard !30 https://github.com/markdlabrecque/railyard/pull/30" ]
}

@test "ry-ref.sh <id>: ticket from meta, PR URL verbatim from meta" {
  make_project railyard
  set_remote railyard https://github.com/markdlabrecque/railyard.git
  printf 'id=27-x\nproject=railyard\nticket=27\nshape=haul\n' > "$RY_HOME/state/27-x.meta"
  run bin/ry-ref.sh 27-x
  [ "$status" -eq 0 ]
  [ "$output" = "railyard #27 https://github.com/markdlabrecque/railyard/issues/27" ]
  printf 'forge=github\npr_url=https://github.com/markdlabrecque/railyard/pull/30\n' >> "$RY_HOME/state/27-x.meta"
  run bin/ry-ref.sh 27-x
  [ "${lines[0]}" = "railyard #27 https://github.com/markdlabrecque/railyard/issues/27" ]
  [ "${lines[1]}" = "railyard !30 https://github.com/markdlabrecque/railyard/pull/30" ]
}

@test "ry-ref.sh <id>: no ticket and no PR is qualified but never linked" {
  make_project acr
  printf 'id=news-filter\nproject=acr\nticket=\nshape=haul\n' > "$RY_HOME/state/news-filter.meta"
  run bin/ry-ref.sh news-filter
  [ "$status" -eq 0 ]
  [ "$output" = "acr news-filter (no ticket, no URL)" ]
  [[ "$output" != *http* ]]
}

@test "ry-ref.sh: bad inputs fail loudly" {
  make_project acr
  run bin/ry-ref.sh nope
  [ "$status" -ne 0 ]; [[ "$output" == *"unknown id"* ]]
  run bin/ry-ref.sh nope '#3'
  [ "$status" -ne 0 ]; [[ "$output" == *"unknown project"* ]]
  run bin/ry-ref.sh acr '#abc'
  [ "$status" -ne 0 ]; [[ "$output" == *"not a number"* ]]
  run bin/ry-ref.sh
  [ "$status" -eq 2 ]; [[ "$output" == *usage:* ]]
}
