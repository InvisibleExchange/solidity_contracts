import React from "react";

export default class LimitOrderForm extends React.Component {
  state = {
    total: null,
    next: null,
    operation: null,
  };

  render() {
    return (
      <div className="form">
        <form>
          <div class="form-group">
            <label for="order_id"> X order_id: </label>
            <input type="number" id="order_id" name="order_id"></input>
          </div>

          <div class="form-group">
            <label for="expiration_timestamp"> X expiration_timestamp: </label>
            <input
              type="number"
              id="expiration_timestamp"
              name="expiration_timestamp"
            ></input>
          </div>

          <div class="form-group">
            <label for="token_spent"> token_spent: </label>
            <input type="number" id="token_spent" name="token_spent"></input>
          </div>

          <div class="form-group">
            <label for="token_received"> token_received: </label>
            <input
              type="number"
              id="token_received"
              name="token_received"
            ></input>
          </div>

          <div class="form-group">
            <label for="amount_spent"> amount_spent: </label>
            <input type="number" id="amount_spent" name="amount_spent"></input>
          </div>

          <div class="form-group">
            <label for="amount_received">
              {" "}
              (*from price) amount_received:{" "}
            </label>
            <input
              type="number"
              id="amount_received"
              name="amount_received"
            ></input>
          </div>

          <div class="form-group">
            <label for="fee_limit"> fee_limit: </label>
            <input type="number" id="fee_limit" name="fee_limit"></input>
          </div>

          <div class="form-group">
            <label for="dest_spent_address"> X dest_spent_address: </label>
            <input
              type="number"
              id="dest_spent_address"
              name="dest_spent_address"
            ></input>
          </div>

          <div class="form-group">
            <label for="dest_received_address">
              {" "}
              X dest_received_address:{" "}
            </label>
            <input
              type="number"
              id="dest_received_address"
              name="dest_received_address"
            ></input>
          </div>

          <div class="form-group">
            <label for="blinding_seed"> X blinding_seed: </label>
            <input
              type="number"
              id="blinding_seed"
              name="blinding_seed"
            ></input>
          </div>

          <div class="form-group">
            <label for="notes_in"> X notes_in: </label>
            <input type="number" id="notes_in" name="notes_in"></input>
          </div>

          <div class="form-group">
            <label for="refund_note"> X refund_note: </label>
            <input type="number" id="refund_note" name="refund_note"></input>
          </div>

          <button type="submit" class="btn btn-primary">
            Submit
          </button>
        </form>
      </div>
    );
  }
}
