#comment out the below if you want no authentication on your web portal (not recommended)
Resque::Server.use(Rack::Auth::Basic) do |user, password|
  [user, password] == ['admin', 'changeyourpassword']
end
