import React, { useState } from "react";
import "./App.css";

import { setGlobalState, getGlobalState, useGlobalState } from "./global_state";

import DepositForm from "./components/deposits";
import LimitOrderForm from "./components/order";
import { UserInfo } from "./components/Home/UserInfo";

export default function App() {
  const user_ = useGlobalState("user");

  const [user, setUser] = useState(user_[0]);

  function handleClick(e) {
    //   e.preventDefault();
    //   let user = getGlobalState("user");
    //   setUserId(user);
  }

  return (
    <div class="container" className="App">
      <UserInfo></UserInfo>
      <div class="container" className="App"></div>
    </div>
  );
}
