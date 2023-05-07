import { createGlobalState } from "react-hooks-global-state";
import { ethers } from "ethers";

// ? Create the initial state
const initialState = {
  user: null,
  provider: new ethers.providers.JsonRpcProvider("http://127.0.0.1:8545/"),
  ws_client: null,
  order_books: {}, // { 12345: { bids: [], asks: [] } }
  index_prices: {}, // { 12345: latest_price }
};
const { setGlobalState, getGlobalState, useGlobalState } =
  createGlobalState(initialState);

export { setGlobalState, getGlobalState, useGlobalState };


