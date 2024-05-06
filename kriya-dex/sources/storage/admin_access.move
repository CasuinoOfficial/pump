module kdx_spot::admin_access {

    // Admin access hot potato token.
    struct AdminAccess {}

    friend kdx_spot::app;
    friend kdx_spot::pool;

    public(friend) fun mint():AdminAccess {
        AdminAccess { }
    }

    public(friend) fun burn(access_token: AdminAccess) {
        let AdminAccess { } = access_token;
    }
}