import React from "react";

export default class DepositForm extends React.Component {
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
            <label for="deposit_id"> deposit_id: </label>
            <input type="number" id="deposit_id" name="deposit_id"></input>
          </div>

          <div class="form-group">
            <label for="deposit_amount"> deposit_amount: </label>
            <input
              type="number"
              id="deposit_amount"
              name="deposit_amount"
            ></input>
          </div>

          <div class="form-group">
            <label for="stark_key"> stark_key: </label>
            <input type="number" id="stark_key" name="stark_key"></input>
          </div>

          <div class="form-group">
            <label for="notes"> notes: </label>
            <input type="number" id="notes" name="notes"></input>
          </div>

          <div class="form-group">
            <label for="signature"> signature: </label>
            <input type="number" id="signature" name="signature"></input>
          </div>

          <button type="submit" class="btn btn-primary">
            Submit
          </button>
        </form>
      </div>
    );
  }
}
