import React from "react";
import { Outlet, Link } from "react-router-dom";
import { getGlobalState } from "../global_state";

export default class Layout extends React.Component {
  render() {
    return (
      <div className="m-3">
        <nav class="navbar navbar-expand-lg navbar-light bg-light">
          <a class="navbar-brand" href="#">
            <h1>Invisible</h1>
          </a>
          <button
            class="navbar-toggler"
            type="button"
            data-toggle="collapse"
            data-target="#navbarNav"
            aria-controls="navbarNav"
            aria-expanded="false"
            aria-label="Toggle navigation"
          >
            <span style={{ color: "blue" }} class="navbar-toggler-icon"></span>
          </button>
          <div class="collapse navbar-collapse" id="navbarNav">
            <ul class="navbar-nav">
              <li class="nav-item active">
                <a class="nav-link" href="#">
                  <Link class="font-weight-bold " to="/">
                    <h4>
                      <span
                        style={{ color: "blue" }}
                        class="badge badge-secondary border border-primary"
                      >
                        Home
                      </span>
                    </h4>
                  </Link>
                </a>
              </li>
              {/* =============================================================== */}
              {/* <li class="nav-item">
                <a class="nav-link" href="#">
                  <Link class="font-weight-bold " to="/deposits">
                    <h4>
                      <span
                        style={{ color: "blue" }}
                        class="badge badge-secondary border border-primary"
                      >
                        Deposits
                      </span>
                    </h4>
                  </Link>
                </a>
              </li> */}
              {/* =============================================================== */}
              {/* <li class="nav-item">
                <a class="nav-link" href="#">
                  <Link class="font-weight-bold " to="/orders">
                    <h4>
                      <span
                        style={{ color: "blue" }}
                        class="badge badge-secondary border border-primary"
                      >
                        Orders
                      </span>
                    </h4>
                  </Link>
                </a>
              </li> */}
              {/* =============================================================== */}
              {/* <li class="nav-item">
                <a class="nav-link" href="#">
                  <Link class="font-weight-bold " to="/perpetuals">
                    <h4>
                      <span
                        style={{ color: "blue" }}
                        class="badge badge-secondary border border-primary"
                      >
                        Perpetuals
                      </span>
                    </h4>
                  </Link>
                </a>
              </li> */}
              {/* =============================================================== */}
              {/* <li class="nav-item">
                <a class="nav-link" href="#">
                  <Link class="font-weight-bold " to="/withdrawals">
                    <h4>
                      <span
                        style={{ color: "blue" }}
                        class="badge badge-secondary border border-primary"
                      >
                        Withdrawals
                      </span>
                    </h4>
                  </Link>
                </a>
              </li> */}
              {/* =============================================================== */}
              {/* <li class="nav-item">
                <a class="nav-link" href="#">
                  <Link class="font-weight-bold " to="/dummy_forms">
                    <h4>
                      <span
                        style={{ color: "blue" }}
                        class="badge badge-secondary border border-primary"
                      >
                        Dummy Forms
                      </span>
                    </h4>
                  </Link>
                </a>
              </li> */}
              {/* =============================================================== */}
              {/* // TODO !!!!!!!!!! */}
              {/* <li class="nav-item">
                <a class="nav-link" href="#">
                  <Link class="font-weight-bold " to="/smart_contracts">
                    <h4>
                      <span
                        style={{ color: "blue" }}
                        class="badge badge-secondary border border-primary"
                      >
                        Smart Contracts
                      </span>
                    </h4>
                  </Link>
                </a>
              </li> */}
              {/* =============================================================== */}
              {/* <li class="nav-item">
                <a class="nav-link" href="#">
                  <Link class="font-weight-bold " to="/controls">
                    <h4>
                      <span
                        style={{ color: "blue" }}
                        class="badge badge-secondary border border-primary"
                      >
                        Controls
                      </span>
                    </h4>
                  </Link>
                </a>
              </li> */}
              {/* =============================================================== */}
              <li class="nav-item">
                <a class="nav-link" href="#">
                  <Link class="font-weight-bold " to="/login">
                    <h4>
                      <span
                        style={{ color: "blue" }}
                        class="badge badge-secondary border border-primary"
                      >
                        Login
                      </span>
                    </h4>
                  </Link>
                </a>
              </li>
            </ul>
          </div>
        </nav>

        <Outlet />
      </div>
    );
  }
}
