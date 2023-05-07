import { Component, useRef, useState } from "react";
import {
  setGlobalState,
  getGlobalState,
  useGlobalState,
} from "../../global_state";

import Dropdown from "react-bootstrap/Dropdown";

export class NoteData extends Component {
  render() {
    const user = getGlobalState("user");

    return (
      <div class="container-fluid border border-success">
        <div class="row p-3 border border-info">
          <div className="col-4 align-items-start border border-warning ">
            <TokenInfoCard token={this.props.token} />
          </div>
          <div className="col-8">
            <NoteCard token={this.props.token} />
          </div>
        </div>
      </div>
    );
  }
}

/**
   * This displays all info about a given note, not needed for the FE
   */
function NoteCard({ token }) {
  const user = getGlobalState("user");

  const indexes = user.noteData[token].map((noteD) => noteD.index);

  const [noteD, setNoteD] = useState(null);

  function handleNoteIdxChange(e) {
    e.preventDefault();

    let note_ = user.noteData[token][e.target.tabIndex];
    setNoteD(note_);
  }

  return (
    <div className="row">
      <div className="col-4">
        <Dropdown>
          <Dropdown.Toggle variant="success" id="dropdown-basic">
            Notes
          </Dropdown.Toggle>

          <Dropdown.Menu>
            {indexes.map((noteIdx, arrIdx) => {
              return (
                <Dropdown.Item
                  tabIndex={arrIdx}
                  key={arrIdx}
                  onClick={handleNoteIdxChange}
                >
                  {noteIdx.toString()}
                </Dropdown.Item>
              );
            })}
          </Dropdown.Menu>
        </Dropdown>
      </div>

      <div className="col-8">
        {noteD ? (
          <div class="card">
            <div class="card-body">
              <h5 class="card-title">Note Info:</h5>
              <h6 class="card-subtitle mb-2 text-muted">
                All the relevent note information
              </h6>
              <ul class="list-group list-group-flush">
                <li class="list-group-item">
                  <b>index</b>: {noteD.index.toString()}
                </li>
                <li class="list-group-item">
                  <b>token</b>: {noteD.token.toString()}
                </li>
                <li class="list-group-item">
                  <b>amount</b>: {noteD.amount.toString()}
                </li>
                <li class="list-group-item">
                  <b>blinding factor</b>: {noteD.blinding.toString()}
                </li>
                <li class="list-group-item">
                  <b>Adress: </b>: [{noteD.address.getX().toString()},{" "}
                  {noteD.address.getY().toString()}]
                </li>
              </ul>
            </div>
          </div>
        ) : (
          <h4>No note selected, select one in the dropdown</h4>
        )}
      </div>
    </div>
  );
}


 /**
   * This displays some info about the users notes and balance for a selected token, not needed for the FE
   */
function TokenInfoCard({ token }) {
  let user = getGlobalState("user");

  let indexesString = "[";
  user.noteData[token]
    .map((n) => n.index)
    .forEach((idx) => (indexesString += idx.toString() + ", "));
  indexesString = indexesString.slice(0, -2);
  if (indexesString.length) {
    indexesString += "]";
  }

  let tokenSymbols = { 12345: "BTC", 54321: "ETH", 55555: "USDC" };

  return (
    <div class="card">
      <div class="card-body">
        <h5 class="card-title">Token Info:</h5>
        <h6 class="card-subtitle mb-2 text-muted">
          All the relevent information for this user and this token
        </h6>
        <ul class="list-group list-group-flush">
          <li class="list-group-item">
            <b>token id</b>: {tokenSymbols[token]}
          </li>
          <li class="list-group-item">
            <b>note indexes for this token</b>:{indexesString}
          </li>
          <li class="list-group-item">
            <b>available amount</b>: {user.getAvailableAmount(token).toString()}
          </li>
        </ul>
      </div>
    </div>
  );
}
