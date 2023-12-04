const { expect } = require("chai");

const { ethers, upgrades } = require("hardhat");

describe("Invisible", function () {
  it("upgrade", async () => {
    const [owner, addr1] = await ethers.getSigners();

    const invisible = await ethers.getContractFactory("Invisible");
    const invisibleV2 = await ethers.getContractFactory("InvisibleV2");

    const instance = await upgrades.deployProxy(invisible, [owner.address], {
      kind: "uups",
    });
    const value1 = await instance.version();

    const upgraded = await upgrades.upgradeProxy(
      await instance.getAddress(),
      invisibleV2,
      { kind: "uups", call: { fn: "initialize", args: [owner.address] } }
    );

    const value2 = await upgraded.version();
    expect(value1.toString()).to.equal("1");
    expect(value2.toString()).to.equal("2");
  });
});
