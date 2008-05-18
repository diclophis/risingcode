
  class Bootstrap < R('/bootstrap')
    def get
      doccom %{security wall}
      raise "bootstrapping"
      @bootstrapping = true
      if false
        @include_openid_delegation = true
        @openid_server = "http://pip.verisignlabs.com/server"
        @openid_delegate = "http://diclophis.pip.verisignlabs.com"
        @openid2_provider = @openid_server #"http://pip.verisignlabs.com/server"
        @X_XRDS_Location = "http://pip.verisignlabs.com/user/diclophis/yadisxrds"
      else
        @include_openid_delegation = false
        render :bootstrap
      end
    end
    def post
      doccom %{security wall}
      raise "bootstrapping"
      first_root_user = User.new
      first_root_user.root = true
      first_root_user.openid_server = @input.openid_server
      first_root_user.openid_delegate = @input.openid_delegate
      first_root_user.openid2_provider = @input.openid2_provider
      first_root_user.x_xrds_location = @input.x_xrds_location
      raise first_root_user.inspect
    end
  end
