import React, { Component, useRef, useState } from "react";
import { getGlobalState } from "../../global_state";

import Dropdown from "react-bootstrap/Dropdown";
import bigInt from "big-integer";

import axios from "axios";
import Form from "react-bootstrap/Form";
import {
  removeNoteFromDb,
  storeNewNote,
} from "../../app_logic/helpers/firebase/firebaseConnection";
import { Note } from "../../app_logic/users/Notes";

export class PositionData extends Component {
  render() {
    const user = getGlobalState("user");

    return (
      <div class="container-fluid border border-success">
        <div class="row p-3 border border-info">
          <div className="col-12">
            <PositionCard token={this.props.token} />
          </div>
        </div>
      </div>
    );
  }
}

/**
 * This displays all info about a given position, not needed for the FE
 */
function PositionCard({ token }) {
  const user = getGlobalState("user");

  const positionIds = user.positionData[token].map((pD) =>
    pD.position_address.toString()
  );

  const [positionData, setPositionData] = useState(null);

  function handleNoteIdxChange(e) {
    e.preventDefault();

    let position_ = user.positionData[token][e.target.tabIndex];
    setPositionData(position_);
  }

  return (
    <div className="row">
      <div className="col-4">
        {token == 12345
          ? "BTC"
          : token == 54321
          ? "ETH"
          : token == 55555
          ? "USDC"
          : "Unknown token"}{" "}
        Positions:
        <Dropdown>
          <Dropdown.Toggle variant="success" id="dropdown-basic">
            Positions
          </Dropdown.Toggle>

          <Dropdown.Menu>
            {positionIds.map((positionId, arrIdx) => {
              return (
                <Dropdown.Item
                  tabIndex={arrIdx}
                  key={arrIdx}
                  onClick={handleNoteIdxChange}
                >
                  {positionId}
                </Dropdown.Item>
              );
            })}
          </Dropdown.Menu>
        </Dropdown>
      </div>

      <div className="col-8">
        {positionData ? (
          <div class="card">
            <div class="card-body">
              <h5 class="card-title">Position Info:</h5>
              <h6 class="card-subtitle mb-2 text-muted">
                All the relevent position information
              </h6>
              <ul class="list-group list-group-flush">
                <li class="list-group-item">
                  <b>position_address</b>: {positionData.position_address}
                </li>
                <li class="list-group-item">
                  <b>order_side</b>: {positionData.order_side}
                </li>
                <li class="list-group-item">
                  <b>synthetic_token</b>: {positionData.synthetic_token}
                </li>
                <li class="list-group-item">
                  <b>position_size</b>: {positionData.position_size}
                </li>
                <li class="list-group-item">
                  <b>margin</b>: {positionData.margin}
                </li>
                <li class="list-group-item">
                  <b>entry_price</b>: {positionData.entry_price}
                </li>
                <li class="list-group-item">
                  <b>liquidation_price</b>: {positionData.liquidation_price}
                </li>
                <li class="list-group-item">
                  <b>last_funding_idx</b>: {positionData.last_funding_idx}
                </li>
                <li class="list-group-item">
                  <b>index</b>: {positionData.index}
                </li>
              </ul>
            </div>

            <ChangeMargin positionData={positionData} />
          </div>
        ) : (
          <h4>No note selected, select one in the dropdown</h4>
        )}
      </div>
    </div>
  );
}

class ChangeMargin extends React.Component {
  constructor(props) {
    super(props);

    this.user = getGlobalState("user");
    this.positionData = props.positionData;

    this.handleSubmit = this.handleSubmit.bind(this);
  }

  componentDidUpdate(_) {
    this.positionData = this.props.positionData;
  }

  /**
   * Because the system is designed only for isolated margin for now and not cross margin, \
   * we can add or remove extra margin to lower liquidation risk or increase it by freeing up some capital.
   * How that fits into the frontend I have no clue...
   */
  handleSubmit(e) {
    e.preventDefault();

    let collateral_decimals = 6n;

    let direction;
    if (e.target[0].checked) {
      direction = "increase";
    } else if (e.target[1].checked) {
      direction = "decrease";
    } else {
      alert("Select order side");
      return;
    }

    let amount = e.target[2].value;

    let margin_change = bigInt(amount).value * 10n ** collateral_decimals;

    console.log(margin_change);

    // if (direction == "decrease" && margin_change >= MARGIN_LEFT?) {}

    let { notes_in, refund_note, close_order_fields, position, signature } =
      this.user.changeMargin(
        this.positionData.position,
        this.positionData.privKey,
        direction,
        margin_change
      );

    let marginChangeMessage = {
      margin_change:
        direction == "increase"
          ? margin_change.toString()
          : (-margin_change).toString(),
      notes_in: notes_in ? notes_in.map((n) => n.toGrpcObject()) : null,
      refund_note: refund_note ? refund_note.toGrpcObject() : null,
      close_order_fields: close_order_fields
        ? close_order_fields.toGrpcObject()
        : null,
      position,
      signature: {
        r: signature[0].toString(),
        s: signature[1].toString(),
      },
    };

    console.log(marginChangeMessage);

    axios
      .post("http://localhost:4000/change_position_margin", marginChangeMessage)
      .then((res) => {
        let marginChangeResponse = res.data.response;

        if (marginChangeResponse.successful) {
          alert("Margin changed successfuly!");

          if (direction == "increase") {
            if (refund_note) {
              storeNewNote(refund_note);
            } else {
              removeNoteFromDb(notes_in[0]);
            }

            for (let i = 1; i < notes_in.length; i++) {
              removeNoteFromDb(notes_in[i]);
            }
          } else {
            // dest_received_address: any, dest_received_blinding
            let returnCollateralNote = new Note(
              close_order_fields.dest_received_address,
              this.positionData.position.collateral_token,
              margin_change,
              close_order_fields.dest_received_blinding,
              marginChangeResponse.return_collateral_index
            );

            storeNewNote(returnCollateralNote);
            console.log(returnCollateralNote);
          }
        } else {
          let msg =
            "Failed to submit order with error: \n" +
            marginChangeResponse.error_message;
          alert(msg);
        }
      });
  }

  render() {
    return (
      <div className="container p-1">
        <h4 className="m-1 pt-1 pb-1">Change margin</h4>

        <form onSubmit={this.handleSubmit}>
          {/* ORDER SIDE */}
          <div className="form-group row">
            <label for="direction" className="col-sm-4 col-form-label-md">
              <h5>direction:</h5>
            </label>
            <div className="col-sm-4">
              <div key="order_side_radio" className="mb-3">
                <Form.Check
                  inline
                  label="Increase"
                  value={"Increase"}
                  name="group1"
                  type="radio"
                  id="Increase"
                  onChange={this.handleOrderSideChange}
                />
                <Form.Check
                  inline
                  label="Decrease"
                  value={"Decrease"}
                  name="group1"
                  type="radio"
                  id="Decrease"
                  onChange={this.handleOrderSideChange}
                />
              </div>
            </div>
          </div>

          {/* AMOUNT */}
          <div className="form-group row">
            <label for="amount" className="col-sm-4 col-form-label-md">
              <h5>Amount</h5>
            </label>
            <div className="col-sm-4">
              <input
                type="number"
                className="form-control"
                id="amount"
                placeholder="amount"
                step="0.001"
                presicion={3}
              ></input>
            </div>
          </div>

          <button type="submit">Change margin</button>
        </form>
      </div>
    );
  }
}
