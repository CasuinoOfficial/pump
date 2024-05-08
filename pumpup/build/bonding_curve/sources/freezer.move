module bonding_curve::freezer {

    /// `Ice` is what happens to an object when it is frozen.
    public struct Ice<T: key + store> has key {
        id: UID,
        obj: T,
    }

    #[allow(lint(freeze_wrapped))]
    /// Only `entry` to never be called in another module. The caller needs
    /// to make an explicit call to `freeze_object` to freeze an object.
    public entry fun freeze_object<T: key + store>(obj: T, ctx: &mut TxContext) {
        transfer::freeze_object(Ice {
            id: object::new(ctx),
            obj,
        })
    }
}