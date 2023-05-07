const { get_max_leverage, LEVERAGE_DECIMALS } = require("./utils");

function consistencyChecks(orderA, orderB, spentAmountA, spentAmountB) {
  // ? Check that the tokens swapped match
  if (
    orderA.token_spent !== orderB.token_received ||
    orderA.token_received !== orderB.token_spent
  ) {
    alert("Tokens swapped do not match");
    throw "Tokens swapped do not match";
  }

  // ? Check that the amounts swapped dont exceed the order amounts
  if (
    orderA.amount_spent < spentAmountA ||
    orderB.amount_spent < spentAmountB
  ) {
    alert("Amounts swapped exceed order amounts");
    throw "Amounts swapped exceed order amounts";
  }

  // Todo: Fees taken

  // ? Verify consistency of amounts swaped
  if (
    spentAmountA * orderA.amount_received >
      spentAmountB * orderA.amount_spent ||
    spentAmountB * orderB.amount_received > spentAmountA * orderB.amount_spent
  ) {
    alert("Amount swapped ratios");
  }
}

function perpConsisencyChecks(orderA, orderB, spentCollateral, spentSynthetic) {
  if (orderA.synthetic_token != orderB.synthetic_token) {
    alert("Tokens swapped do not match");
    throw "Tokens swapped do not match";
  }

  // ? Checks if order sides are different and returns the long order as orderA
  if (orderA.order_side != "Long" || orderB.order_side != "Short") {
    let tempOrder = orderA;
    orderA = orderB;
    orderB = tempOrder;

    if (orderA.order_side != "Long" || orderB.order_side != "Short") {
      alert("Order side missmatch");
      throw "Order side missmatch";
    }
  }

  // ? Check that the amounts swapped don't exceed the order amounts
  if (
    orderA.collateral_amount < spentCollateral ||
    orderB.synthetic_amount < spentSynthetic
  ) {
    alert("Amounts swapped exceed order amounts");
    throw "Amounts swapped exceed order amounts";
  }

  if (
    spentCollateral * orderA.synthetic_amount >
      spentSynthetic * orderA.collateral_amount ||
    spentSynthetic * orderB.collateral_amount >
      spentCollateral * orderB.synthetic_amount
  ) {
    alert("Amount swapped ratios are inconsistent");
    throw "Amount swapped ratios are inconsistent";
  }

  // Todo: Fees taken
}

// ===================================================================================

function checkPerpOrderValidity(
  user,
  orderSide,
  posEffectType,
  expirationTime,
  positionAddress,
  syntheticToken,
  syntheticAmount,
  collateralToken,
  collateralAmount,
  initialMargin,
  feeLimit
) {
  if (
    !expirationTime ||
    !syntheticToken ||
    !syntheticAmount ||
    feeLimit == null ||
    !orderSide
  ) {
    console.log("Please fill in all fields");
    throw "Unfilled fields";
  }

  if (posEffectType == "Open") {
    // let maxLeverage = get_max_leverage(syntheticToken, syntheticAmount);
    // let leverage =
    //   (Number.parseFloat(collateralAmount) / Number.parseFloat(initialMargin)) *
    //   10 ** LEVERAGE_DECIMALS;

    // if (leverage > maxLeverage) {
    //   console.log(
    //     `Leverage is too high. Max leverage is ${
    //       maxLeverage / 10 ** LEVERAGE_DECIMALS
    //     }`
    //   );
    //   throw "invalid leverage";
    // }

    if (!collateralToken || !initialMargin) {
      console.log("Please fill in all fields");
      throw "Unfilled fields";
    }

    if (initialMargin > user.getAvailableAmount(collateralToken)) {
      console.log(collateralToken);
      console.log(initialMargin);
      console.log(user.getAvailableAmount(collateralToken));
      console.log("Insufficient balance");
      throw "Insufficient balance";
    }
  } else {
    if (!positionAddress) {
      console.log("Please fill in all fields");
      throw "Unfilled fields";
    }

    let position = user.positionData[syntheticToken].find(
      (pos) => pos.position_address == positionAddress
    );

    if (!position) {
      console.log("Position does not exist");
      throw "order invalid";
    }
  }

  if (expirationTime <= 3 || expirationTime > 1000) {
    console.log("Expiration time must be between 4 and 1000 hours");
    throw "Exipration time invalid";
  }
}

module.exports = {
  checkPerpOrderValidity,
};
