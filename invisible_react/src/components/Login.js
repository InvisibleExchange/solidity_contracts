import { Component, useRef, useState } from "react";
import { Routes, Route, useNavigate } from "react-router-dom";

import User from "../app_logic/users/Invisibl3User";
import firebaseConnection from "../app_logic/helpers/firebase/firebaseConnection";
import LoadingSpinner from "./helpers/LoadingSpinner/LoadingSpinner";

import { setGlobalState } from "../global_state";
import { trimHash } from "../app_logic/users/Notes";

import axios from "axios";

export default class Login extends Component {
  render() {
    return (
      <div className="container">
        <div className="row pt-5">
          <div className="col-4"></div>
          <div className="col-4">
            <LoginForm></LoginForm>
          </div>
          <div className="col-4"></div>
        </div>
      </div>
    );
  }
}

export async function getActiveOrders(order_ids, prep_order_ids) {
  console.log("prep_order_ids", prep_order_ids);

  return await axios
    .post("http://localhost:4000/get_orders", { order_ids, prep_order_ids })
    .then((res) => {
      let order_response = res.data.response;

      let badOrderIds = order_response.bad_order_ids;
      let orders = order_response.orders;
      let badPerpOrderIds = order_response.bad_perp_order_ids;
      let perpOrders = order_response.perp_orders;

      return { badOrderIds, orders, badPerpOrderIds, perpOrders };
    })
    .catch((err) => {
      alert(err);
    });
}

function LoginForm() {
  const [isLoading, setIsLoading] = useState(false);

  const inputRef = useRef(null);
  const navigate = useNavigate();

  async function handleSubmit(e) {
    e.preventDefault();
    setIsLoading(true);

    let privKey = inputRef.current.value;

    let user = User.fromPrivKey(privKey);

    await user.login();

    let { badOrderIds, orders, badPerpOrderIds, perpOrders } =
      await getActiveOrders(user.orderIds, user.perpetualOrderIds);

    await user.handleActiveOrders(
      badOrderIds,
      orders,
      badPerpOrderIds,
      perpOrders
    );

    setIsLoading(false);

    // ? Set up ws connection ————————————————————————————————————————————————————

    setGlobalState("user", user);

    navigate("/");
  }

  return (
    <div>
      {isLoading ? (
        <LoadingSpinner />
      ) : (
        <form>
          <div className="form-group">
            <label for="priv_key">Starknet Private key</label>
            <input
              ref={inputRef}
              type="text"
              className="form-control"
              id="priv_key"
              placeholder="0x..."
            ></input>
          </div>
          <button
            type="login"
            className="btn btn-primary"
            onClick={handleSubmit}
          >
            Login
          </button>
        </form>
      )}
    </div>
  );
}

// import React from 'react';
// import { Redirect } from 'react-router-dom';

// class MyComponent extends React.Component {
//   state = {
//     redirect: false
//   }
//   setRedirect = () => {
//     this.setState({
//       redirect: true
//     })
//   }
//   renderRedirect = () => {
//     if (this.state.redirect) {
//       return <Redirect to='/target' />
//     }
//   }
//   render () {
//     return (
//        <div>
//         {this.renderRedirect()}
//         <button onClick={this.setRedirect}>Redirect</button>
//        </div>
//     )
//   }
// }
