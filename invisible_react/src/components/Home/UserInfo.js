import { Component, useRef, useState } from "react";
import { ethers } from "ethers";

export function UserInfo() {
  const [signer, setSigner] = useState(false);

  async function handleRefresh(e) {
    e.preventDefault();

    // A Web3Provider wraps a standard Web3 provider, which is
    // what MetaMask injects as window.ethereum into each page
    const provider = new ethers.providers.Web3Provider(window.ethereum);

    // MetaMask requires requesting permission to connect users accounts
    await provider.send("eth_requestAccounts", []);

    // The MetaMask plugin also allows signing transactions to
    // send ether and pay to change state within the blockchain.
    // For this, you need the account signer...
    const signer = provider.getSigner();

    setSigner(signer);

    // signer.signMessage(Buffer.from("Hello, world!"))

    console.log(signer);
  }

  async function createStarkKey(e) {
    e.preventDefault();

    let sig = await signer.signMessage(
      "Sign this message to access your Invisibl3 account. \nIMPORTANT: Only sign this message on Invisible.com!!"
    );

    console.log(sig);
  }

  /**
   * This displays all the basic user information, it was only for testing shouldnt have to see this on the real frontend
   */
  return (
    <div class="container">
      <button onClick={handleRefresh} className="m-5 btn btn-primary">
        Connect wallet
      </button>
      <div> </div>
      <button onClick={createStarkKey} className="m-5 btn btn-primary">
        Create StarkKey
      </button>
    </div>
  );
}
