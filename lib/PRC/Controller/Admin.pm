package PRC::Controller::Admin;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

use PRC::Constants;
use List::Util qw/any first/;

=encoding utf8

=head1 NAME

PRC::Controller::Admin - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 auto

Before reaching any action in this controller, confirm user has admin powers.
This is currently hardcoded to one user. Everyone else will get a 404.
If we need more admins/roles in future we can build a separate admin/role table.

=cut

sub auto :Private {
  my ($self, $c) = @_;
  my $user = $c->user;

  if ($user && ($user->github_id == 1781335) && ($user->github_login eq 'kyzn')){
    $c->stash({ show_admin_navbar => 1, hide_navbar => 1, hide_footer => 1 });
    return 1;
  }

  # Default to 404
  $c->response->body('Page not found.');
  $c->response->status(404);
  $c->detach;
}


=head2 /admin

Redirect to /admin/numbers

=cut

sub admin :Path('/admin') :Args(0) {
  my ($self, $c) = @_;
  $c->response->redirect('/admin/numbers',303);
  $c->detach;
}

=head2 /admin/numbers

Basic numbers

=cut

sub numbers :Path('/admin/numbers') :Args(0) {
  my ($self, $c) = @_;

  my @users = $c->model('PRCDB::User')->all;
  my @repos = $c->model('PRCDB::Repo')->all;
  my @orgs  = $c->model('PRCDB::Org')->all;
  my @assignments = $c->model('PRCDB::Assignment')->all;

  my $stats = {
    user_count            => scalar(@users),
    tos_user_count        => scalar(grep {$_->has_accepted_latest_terms} @users),
    deactivated_user      => scalar(grep {$_->is_deactivated && !$_->scheduled_delete_time} @users),
    to_be_deleted_user    => scalar(grep {$_->scheduled_delete_time} @users),
    assignment_user_count => scalar(grep {$_->is_receiving_assignments} @users),
    synced_personal_repos => scalar(grep {$_->last_personal_repo_sync_time} @users),
    synced_org_repos      => scalar(grep {$_->last_org_repo_sync_time} @users),

    all_repo_count => scalar(@repos),
    all_repo_opted => scalar(grep {!$_->gone_missing && $_->accepting_assignees} @repos),
    per_repo_count => scalar(grep {!$_->org_id} @repos),
    per_repo_opted => scalar(grep {!$_->gone_missing && $_->accepting_assignees && !$_->org_id} @repos),
    org_count      => scalar(@orgs),
    org_repo_count => scalar(grep {$_->org_id} @repos),
    org_repo_opted => scalar(grep {!$_->gone_missing && $_->accepting_assignees && $_->org_id} @repos),

    assignment_total => scalar(@assignments),
    assignment_open  => scalar(grep {$_->status == ASSIGNMENT_OPEN} @assignments),
    assignment_skip  => scalar(grep {$_->status == ASSIGNMENT_SKIPPED} @assignments),
    assignment_done  => scalar(grep {$_->status == ASSIGNMENT_DONE} @assignments),
  };

  $c->stash({
    template   => 'static/html/admin/numbers.html',
    active_tab => 'numbers',
    %$stats,
  });

}

=head2 /admin/users

List users.

=cut

sub users :Path('/admin/users') :Args(0) {
  my ($self, $c) = @_;

  my @users = $c->model('PRCDB::User')->search({},{
    prefetch => ['repos','assignments','orgs'],
  })->all;
  my @assignments = $c->model('PRCDB::Assignment')->all;

  @users = map {{
    user_id             => $_->user_id,
    accepted_latest_tos => $_->has_accepted_latest_terms ? "Y" : "",
    github_login        => $_->github_login,
    deactivation_status => _yymmdd($_->scheduled_delete_time) ||
                           ($_->is_deactivated ? "Y" : ""),

    last_login_time              => _yymmdd($_->last_login_time),
    last_personal_repo_sync_time => _yymmdd($_->last_personal_repo_sync_time),
    last_org_repo_sync_time      => _yymmdd($_->last_org_repo_sync_time),
    org_count                    => int(scalar($_->orgs)) || '',

    assignment_status     => $_->is_receiving_assignments ? "Y" : "",
    open_assignment_month => _get_open_assignment_month_sortable($_->assignments),
    assignments_total     => int($_->assignments->count) || '',
    assignments_done      => (scalar(grep {$_->status == ASSIGNMENT_DONE} $_->assignments))    || '',
    assignments_skipped   => (scalar(grep {$_->status == ASSIGNMENT_SKIPPED} $_->assignments)) || '',

    %{_get_repo_counts($_)},

    %{_get_assignee_counts($_,@assignments)},
  }} @users;

  $c->stash({
    users      => \@users,
    template   => 'static/html/admin/users.html',
    active_tab => 'users',
  });

}

=head2 user

=cut

sub user :Path('/admin/user') :Args(1) {
  my ($self, $c, $id) = @_;
  my $user = $c->model('PRCDB::User')->find($id);
  my @taken = $user->assignments_taken;
  my @given = $user->assignments_given;

  $c->stash({
    taken       => \@taken,
    given       => \@given,
    template    => 'static/html/admin/user.html',
  });
}

=head2 /admin/assignment-central

List users that are waiting for assignments.
List repos that are waiting for users.

=cut

sub assignment_central :Path('/admin/assignment-central') :Args(0) {
  my ($self, $c) = @_;

  my $user_subquery = $c->model('PRCDB::Assignment')->search({
    'me.user_id' => { '=' => \'sub.user_id' },
    '-or' => [
      { 'sub.status' => ASSIGNMENT_OPEN },
      { 'sub.month'  => { '>=' => \'strftime("%Y-%m","now")' }},
    ],
  },{
    from => { sub => 'assignment'},
  })->get_column('sub.assignment_id')->as_query;

  my @users = $c->model('PRCDB::User')->search({
    tos_agree_time => {'>=', LATEST_LEGAL_DATE->ymd},
    is_receiving_assignments => 1,
    is_deactivated => 0,
    'NOT EXISTS' => $user_subquery,
  },{
    prefetch => ['assignments', {'user_langs' => 'lang'}],
  })->all;

  @users = map {{
    user_id             => $_->user_id,
    github_login        => $_->github_login,
    github_email        => $_->github_email,
    langs               => $_->active_user_langs_string,
    %{$_->received_assignment_count},
  }} @users;

  my $repo_subquery = $c->model('PRCDB::Assignment')->search({
    'me.repo_id' => { '=' => \'sub.repo_id' },
    'julianday("now")' => { '<=' => \'julianday(month) + 45' },
  },{
    from => { sub => 'assignment'},
  })->get_column('sub.assignment_id')->as_query;

  my @repos = $c->model('PRCDB::Repo')->search({
    'me.accepting_assignees' => 1,
    'me.gone_missing'        => 0,
    'user.tos_agree_time'    => {'>=', LATEST_LEGAL_DATE->ymd},
    'user.is_deactivated'    => 0,
    'NOT EXISTS'             => $repo_subquery,
  },{
    join     => 'user',
    prefetch => ['assignments','org','user'],
  })->all;

  @repos = map {{
    repo_id   => $_->repo_id,
    user_id   => $_->user_id,
    user_name => $_->user->github_login,
    org_id    => $_->org_id // '-',
    org_name  => ( ($_->org) ? ($_->org->github_login) : ''),
    name      => $_->github_full_name,
    lang      => $_->github_language,
    issues    => $_->github_open_issues_count,
    stars     => $_->github_stargazers_count,
    assignment_count => scalar($_->assignments),
  }} @repos;

  $c->stash({
    users      => \@users,
    repos      => \@repos,
    template   => 'static/html/admin/assignment-central.html',
    active_tab => 'assignment-central',
  });

}

sub _yymmdd {
  my ($datetime) = @_;
  return '' unless $datetime;
  return $datetime =~ s/^\d{2}(\d{2})-(\d{2})-(\d{2}).*/$1$2$3/r;
}

sub _get_open_assignment_month_sortable {
  my @assignments = @_;
  my $open_assignment = first {$_->status == ASSIGNMENT_OPEN} @assignments;
  return "" unless $open_assignment;
  return $open_assignment->month_sortable;
}

sub _get_assignee_counts {
  my ($user, @assignments) = @_;
  my @repos = $user->repos->all;
  my @repo_ids = map {$_->repo_id} @repos;

  my $assignees_total = 0;
  my $assignees_open  = 0;
  my $assignees_skip  = 0;
  my $assignees_done  = 0;

  foreach my $assignment (@assignments){
    if ( any {$assignment->repo_id eq $_} @repo_ids ){
      $assignees_total++;
      if ($assignment->status eq ASSIGNMENT_DONE){
        $assignees_done++;
      } elsif ($assignment->status eq ASSIGNMENT_SKIPPED){
        $assignees_skip++;
      } else {
        $assignees_open++;
      }
    }
  }

  return {
    assignees_total => $assignees_total || '',
    assignees_open  => $assignees_open  || '',
    assignees_skip  => $assignees_skip  || '',
    assignees_done  => $assignees_done  || '',
  };
}

sub _get_repo_counts {
  my ($user) = @_;
  my @repos = grep {!$_->gone_missing} $user->repos->all;

  my $per_repos_tot = grep {!$_->org_id} @repos;
  my $per_repos_opt = grep {!$_->org_id && $_->accepting_assignees} @repos;
  my $org_repos_tot = grep {$_->org_id} @repos;
  my $org_repos_opt = grep {$_->org_id && $_->accepting_assignees} @repos;
  my $all_repos_tot = $org_repos_tot + $per_repos_tot;
  my $all_repos_opt = $org_repos_opt + $per_repos_opt;

  return {
    personal_repos_total    => $per_repos_tot || '',
    personal_repos_opted_in => $per_repos_opt || '',
    org_repos_total         => $org_repos_tot || '',
    org_repos_opted_in      => $org_repos_opt || '',
    all_repos_total         => $all_repos_tot || '',
    all_repos_opted_in      => $all_repos_opt || '',
  };
}

__PACKAGE__->meta->make_immutable;

1;
