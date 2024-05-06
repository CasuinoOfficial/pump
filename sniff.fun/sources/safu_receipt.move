module sniff_dot_fun::safu_receipt {
    use sui::balance::{Self, Balance};
    use sui::sui::{SUI};

    /* friend sniff_dot_fun::meme; */
    /* friend sniff_dot_fun::kriya_adapter; */

    // error codes
    const EInvalidSuiBalance: u64 = 0;
    const EInvalidMemeBalance: u64 = 1;
    const EReceiptNotEmpty: u64 = 3;

    public struct SafuReceipt<phantom T> {
        bc_id: ID,
        target: u64,
        sui_balance: Balance<SUI>,
        meme_balance: Balance<T>,
        sui_balance_val: u64,
        meme_balance_val: u64,
        target_pool_id: ID
    }

    public(package) fun mint<T>(
        target: u64,
        sui_balance: Balance<SUI>,
        meme_balance: Balance<T>,
        bc_id: ID,
    ): SafuReceipt<T> {
        assert!(balance::value<SUI>(&sui_balance) > 0, EInvalidSuiBalance);
        assert!(balance::value<T>(&meme_balance) > 0, EInvalidMemeBalance);

        SafuReceipt {
            bc_id: bc_id,
            target: target,
            sui_balance_val: balance::value<SUI>(&sui_balance),
            meme_balance_val: balance::value<T>(&meme_balance),
            sui_balance: sui_balance,
            meme_balance: meme_balance,
            target_pool_id: object::id_from_address(@0x0)
        }
    }

    public(package) fun extract_assets<T>(
        self: &mut SafuReceipt<T>
    ): (Balance<SUI>, Balance<T>) {
        let base_val = balance::value(&self.sui_balance);
        let meme_val = balance::value(&self.meme_balance);

        let sui_balance = balance::split<SUI>(&mut self.sui_balance, base_val);
        let meme_balance = balance::split<T>(&mut self.meme_balance, meme_val);

        (sui_balance, meme_balance)
    }

    #[allow(unused_variable)]
    public(package) fun burn<T>(self: SafuReceipt<T>): (ID, u64, u64, u64, ID) {
        let SafuReceipt {
            bc_id, 
            target, 
            sui_balance, 
            meme_balance, 
            sui_balance_val, 
            meme_balance_val, 
            target_pool_id
        } = self;
        
        assert!(balance::value<SUI>(&sui_balance) == 0, EReceiptNotEmpty);
        assert!(balance::value<T>(&meme_balance) == 0, EReceiptNotEmpty);

        balance::destroy_zero<SUI>(sui_balance);
        balance::destroy_zero<T>(meme_balance);

        (bc_id, target, sui_balance_val, meme_balance_val, target_pool_id)
    }

    public(package) fun target<T>(self: &SafuReceipt<T>): u64 { self.target }
}