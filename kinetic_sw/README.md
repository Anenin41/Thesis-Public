# Kinetic Shallow-Water Solver with Recharge (1D)

This repository contains a simple Python implementation of a 1D finite-volume kinetic solver for the Shallow-Water equations with an optional recharge term (rainfall minus infiltration). Numerical fluxes are computed using an upwind kinetic flux-splitting approach. The implementation of this numerical scheme is intentionally minimal, and its aim is to serve as the foundation to something more advanced.

---

## Contents

- `kinetic_sw_recharge.py`  
  Main solver script: model definition, kinetic flux, finite-volume update, CFL time stepping, and plotting utilities.

---

## Mathematical Model (plain text)

Variables:
- `h(x,t)`: water depth
- `u(x,t)`: depth-averaged velocity
- `q = h*u`: discharge
- `Z(x)`: bed elevation
- `S = R - I`: recharge (rainfall R minus infiltration I)

Equations solved (1D SWE with recharge):

Mass:
- `d/dt h + d/dx (h*u) = S`

Momentum:
- `d/dt (h*u) + d/dx (h*u^2 + 0.5*g*h^2) = -g*h*dZ/dx + S*u`

Default configuration in the script:
- flat bed: `Z(x) = 0`
- no infiltration: `I = 0` (implemented by setting `I = None`)
- uniform rainfall controlled by `rain_rate`. If `rain_rate = 0`, then the script recovers the original SWE dam break scenario.

---

## Numerical Method (High-Level)

### 1) Finite-Volume Discretization
The solver stores cell averages of conservative variables:
- `U_i = [ h_i, (h*u)_i ]`

A standard finite-volume update is applied:
- `U_i^{n+1} = U_i^n - (dt/dx) * (F_{i+1/2}^n - F_{i-1/2}^n) + dt * (sources)`

Fluxes are computed at cell interfaces (there are N cells and N+1 interfaces).

### 2) Kinetic Flux Splitting (core idea)
Instead of a classical Riemann solver, interface fluxes are computed from a kinetic representation, as is documented in the paper this method is drawn from.

- Each cell state `(h,u)` is mapped to a Maxwellian distribution `M(h,u; xi)`, where `xi` is an auxiliary "kinetic" velocity.
- At each interface, I use an upwind scheme in `xi`:
  - for `xi >= 0` (right-moving), take M from the left cell
  - for `xi < 0` (left-moving), take M from the right cell
- Fluxes are computed as moments of the upwinded distribution:
  - mass flux:      integral of `xi * M_up(xi) over xi`
  - momentum flux:  integral of `xi^2 * M_up(xi) over xi`
- The integrals are approximated with a simple uniform-grid quadrature over a fixed `xi`-grid.

Notes:
- The kinetic grid size (`N_xi`) and kinetic range (`xi_max_factor`) influence smoothness and accuracy.
- This is the simplest kinetic split and implementation possible. More advanced implementations and testing was not the scope of this scheme at this point of the development.

### 3) Time Stepping (CFL)
The scheme uses explicit Euler time stepping with a CFL-limited timestep:
- `dt = CFL * dx / max_i( |u_i| + sqrt(2*g*hi) )`

The `sqrt(2*g*h)` term is consistent with the compact support of the Maxwellian used.

### 4) Source Terms and Dry-Cell Handling
Source terms included:
- Recharge in mass: `+S`
- Recharge in momentum: `+S*u`
- Bed slope in momentum: `-g*h*(dZ/dx)`, computed by finite differences

Dry/near-dry handling:
- velocity is computed as `u = (h*u) / max(h, h_eps)` to avoid division by zero
- after each update, `h` is clipped to be non-negative and momentum is set to zero where `h < h_eps`, with `h_eps` being a user defined tolerance for handling dry cells.

Boundary conditions:
- reflective wall boundaries

Notes:
- It is worthwhile to note that because the boundaries are reflective, if the simulation is to be left running for an extended period of time, the wave will bounce at the walls and back into the computational domain, effectively trashing the solution.

---

## What You Should Expect to See

### Dam-break benchmark (default)
With `rain_rate = 0.0` and `Z = 0`, the code reproduces the standard 1D SWE dam-break structure. When `rain_rate not 0.0`, then a uniform rainfall phenomenon is introduced into the model. This of course will have an effect on the dam break scenario. Simply modify line 438 of `kinetic_sw_recharge.py` with a mediocre number (say `5.0`) to see this.

The script plots:
- bed elevation `Z(x)` and free surface elevation `eta(x) = h(x) + Z(x)`
- water depth `h(x)`
- velocity `u(x)`
- discharge `q(x) = h(x) * u(x)`

Because the method is first-order in space and uses finite `xi`-grid quadrature, the profiles can appear "stair-like". In this case, increase resolution (`N` and/or `N_xi`).

---

## Installation

Requirements:
- Python 3.10+
- NumPy
- Matplotlib

Install dependencies:
- Make a virtual environment `python3 -m venv <your_env_name>`
- Activate the virtual environment `source <your_env_name>/bin/activate`
- Install dependencies `pip install -r requirements.txt`
- You are good to go! Run the simulation with `python3 kinetic_sw_recharge.py`
