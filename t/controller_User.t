use strict;
use warnings;
use Test::More;


use Catalyst::Test 'PRC';
use PRC::Controller::User;

ok( request('/my-profile')->is_success, 'Request should succeed' );
ok( request('/my-assignment')->is_success, 'Request should succeed' );
ok( request('/my-repos')->is_success, 'Request should succeed' );
done_testing();