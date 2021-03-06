requires 'Catalyst::Runtime';
requires 'Catalyst::Plugin::ConfigLoader';
requires 'Catalyst::Plugin::Authentication';
requires 'Catalyst::Action::RenderView';
requires 'Catalyst::Helper';
requires 'Catalyst::Helper::View::TT';
requires 'Catalyst::Plugin::Session::State::Cookie';
requires 'Catalyst::Plugin::Session::Store::Memcached';
requires 'Catalyst::Plugin::Static::Simple';
requires 'Config::General';
requires 'Catalyst::Plugin::Unicode';
requires 'DBIx::Class::Schema::Loader';
requires 'DBIx::Class::TimeStamp';
requires 'FCGI';
requires 'FCGI::ProcManager';
requires 'HTTP::Server::Simple';
requires 'HTML::FormHandler';
requires 'Net::SSLeay' => '1.88';
requires 'IO::Socket::SSL';
requires 'JSON::XS';
requires 'LWP::UserAgent';
requires 'LWP::Protocol::https';
requires 'Moose';
requires 'MooseX::NonMoose';
requires 'namespace::autoclean';
requires 'App::Sqitch';
requires 'Task::Catalyst::Tutorial';
requires 'Test2::V0';
requires 'WWW::Mechanize';
requires 'YAML';
test_requires 'Test::More' => '0.88';
