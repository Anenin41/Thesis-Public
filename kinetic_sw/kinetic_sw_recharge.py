# Kinetic Solver for SWE + Recharge drawn from Paper [5] #

# Model (1D SWE with Rainfall)
# Let:
# - h(x, t)     :   water depth
# - u(x, t)     :   depth-averaged velocity
# - q = h u     :   discharge
# - Z(x)        :   bed elevation
# - S = R - I   :   recharge source term (Rainfall - Infiltration)

# PDEs:
# - dt(h) + dx(h u) = S
# - dt(h u) + dx(h u^2 + 1/2 g h^2) = - g h dx Z + S u

# Numerical Scheme:
# - Finite volume scheme on a uniform 1D grid (cell averages)
# - For interface fluxes use kinetic flux splitting:
#   1) Map each cell state (h, u) to a Maxwellian M(h, u; xi)
#   2) Upwind in kinetic velocity xi at each interface
#   3) Compute flux moments by quadrature over xi
# - Time stepping: explicit Euler scheme with a CFL modified timestep.

# Packages
import numpy as np
import matplotlib.pyplot as plt

# Constants
g = 9.81

def chi(omega: np.ndarray) -> np.ndarray:
    """
    Weight funtion used to define the kinetic Maxwellian.

    The implementation uses a compact support as is also the case in the paper:
        chi(omega) = (1 / (pi g)) * sqrt( max(0, 2g - omega^2) )

    Properties (by design):
        - chi is symmetric and non-negative
        - chi has compact support, |omega| <= sqrt(2g)
        - it is chosen so the Maxwellian moments produce the SWE variables

    Parameters:
        omega   :   np.ndarray
        Array of omega values (dimensionless kinetic velocity)

    Returns:
        np.ndarray
        chi(omega) evaluated element-wise.
    """
    # The exact choice is drawn from the paper, treat it numerically so near-zero
    # values are friendly for the scheme
    inside = 2.0 * g - omega**2
    inside = np.maximum(inside, 0.0)

    output = (1.0 / (np.pi * g)) * np.sqrt(inside)
    return output

def maxwellian(h: float, 
               u:float, 
               xi: np.ndarray, 
               h_eps: float = 1e-8,
               ) -> np.ndarray:
    """
    Kinetic Maxwellian M(h, u; xi) used by the kinetic flux splitting.

    Definition:
        M(h, u; xi) = sqrt(h) * chi( (xi - u) / sqrt(h) )

    Interpretation:
        - xi is an auxiliary (kinetic) velocity variable
        - M acts like a velocity distribution and is the connection between
        microscopic and macroscopic quantities (kinetic -> SWE)

    Near-dry handling:
        - If h <= h_eps, return M = 0 to avoid division by zero when the water
        height is below a certain user-defined tolerance.

    Parameters:
        h   :   float
            Water depth
        u   :   float
            Depth-averaged velocity
        xi  :   np.ndarray
            Kinetic velocity grid
        h_eps   :   float, optional
            Minimum depth threshold used to detect dryness

    Returns:
        np.ndarray
            Array M(xi) on the provided xi-grid
    """
    # Treat near-zero cases with a minimum height tolerance
    if h <= h_eps:
        return np.zeros_like(xi)

    # The rest is the same as the equations of the paper, also listed in the
    # documentation of this function
    sqrt_h = np.sqrt(h)
    omega = (xi - u) / sqrt_h
    output = sqrt_h * chi(omega)

    return output

def kinetic_flux(hL: float, 
                 uL: float,
                 hR: float,
                 uR: float,
                 xi: np.ndarray,
                 dxi: float) -> tuple[float, float]:
    """
    Compute the numerical interface flux using a simple upwind scheme in xi.

    Given left & right states (hL, uL), (hR, uR) define:
        M_L(xi) = M(hL, uL, xi)
        M_R(xi) = M(hR, uR, xi)

    Upwind kinetic distribution:
        M_up(xi)= M_L(xi)   for xi >= 0
                = M_R(xi)   for xi < 0

    Then the interface fluxes are the xi-moments:
        F_mass  = integral xi M_up(xi) dxi              (mass equation)
        F_mom   = integral xi^2 M_up(xi) dxi            (momentum equation)

    Integrals in this code are estimated by simple numerical quadrature.

    Parameters:
        hL, uL  :   float
            Left cell state (depth & velocity)
        hR, uR  :   float
            Right cell state (depth & velocity)
        xi  :   np.ndarray
            Kinetic velocity grid
        dxi :   float
            Kinetic grid spacing

    Returns:
        (F_mass, F_mom) :   tuple[float, float]
            Numerical fluxes at the interface:
                - F_mass approximates hu
                - F_mom  approximates hu^2 + 1/2 g h^2
    """
    ML = maxwellian(hL, uL, xi)
    MR = maxwellian(hR, uR, xi)

    # Upwind in kinetic space: xi>0 travels left->right, xi<0 travels right->left
    M_up = np.where(xi >= 0.0, ML, MR)

    # Mass & Momentum
    F_mass = np.sum(xi * M_up) * dxi
    F_mom = np.sum(xi**2 * M_up) * dxi

    return float(F_mass), float(F_mom)

def max_wave_speed(h: np.ndarray,
                   u: np.ndarray,
                   h_eps: float = 1e-8,
                   ) -> float:
    """
    Estimate the maximum propagation speed for CLF time stepping.

    In this kinetic setup, an estimate is:
        s_max = max_i ( |u_i| + sqrt(2 g h_i) )

    Parameters:
        h, u    :   np.ndarray
            Current depth and velocity fields
        h_eps   :   float, optional
            Minimum depth threshold to avoid dry cells.

    Returns:
        float
            Maximum wave speed s_max
    """
    h_pos = np.maximum(h, h_eps)
    c = np.sqrt(2.0 * g * h_pos)
    return float(np.max(np.abs(u) + c))

# Explicit Finite Volume step: flux divergence + source + dry-cell handling
def step_kinetic(h: np.ndarray,
                 hu: np.ndarray,
                 Z: np.ndarray,
                 R: np.ndarray,
                 I: np.ndarray | None,
                 dx: float,
                 dt: float,
                 xi: np.ndarray,
                 dxi: float,
                 h_eps: float = 1e-8) -> tuple[np.ndarray, np.ndarray]:
    """
    Advance thhe state (h, hu) by one explicit time step.

    Update rule:
        U_i^{n+1} = U_i^n - (dt/dx) (F_{i+1/2} - F_{i-1/2} + dt * Source_i
    
    with U = [h, hu]^T

    Source terms included in this baseline implementation:
        - Recharge in mass:         + S
        - Recharge in momentum:     + S u
        - Bed slope in momentum:    + (- g h dxZ)

    Parameters:
        h   :   np.ndarray
            Cell averaged water depths
        hu  :   np.ndarray
            Cell averaged discharge
        Z   :   np.ndarray
            Bed elevation at cell centers
        R   :   np.ndarray
            Rainfall rate
        I   :   np.ndarray
            Infiltration rate, or None for no infiltration
        dx  :   float
            Spatial grid spacing
        dt  :   float
            Time step
        xi, dxi :   np.ndarray, float
            Kinetic velocity grid and spacing for numerical quadrature
        h_eps   :   float, optimal
            Minimum depth threshold to avoid dry cells

    Returns:
        (h_new, hu_new) :   tuple[np.ndarray, np.ndarray]
            Updated variables after one time step
    """
    # Fetch size
    N = h.size

    # Recharge source term, S = R - I
    S =  R.copy()
    if I is not None:
        S = S - I

    # Avoid division by zero (dry-cell safety)
    h_pos = np.maximum(h, h_eps)
    u = hu / h_pos

    # Fluxes at interfaces (N+1 interfaces for N cells)
    F_mass = np.zeros(N+1)
    F_mom = np.zeros(N+1)

    # Boundary conditions are REFLECTIVE. So if I run this thing long enoung,
    # then at some point I should see this depicted in the figures.
    for i in range(N+1):
        if i == 0:
            # Left boundary, a simple reflective wall
            hL, uL = h[0], -u[0]
            hR, uR = h[0], u[0]
        elif i == N:
            # Right boundary: another reflective wall
            hL, uL = h[N - 1], u[N - 1]
            hR, uR = h[N - 1], -u[N - 1]
        else:
            # Interior interface: cells i-1 (left) and i (right)
            hL, uL = h[i - 1], u[i - 1]
            hR, uR = h[i], u[i]

        # Get the fluxes
        Fm, Fq = kinetic_flux(hL, uL, hR, uR, xi, dxi)
        F_mass[i] = Fm
        F_mom[i] = Fq

    # A bed slope source for momentum: -g * h * dx(Z)
    # In the interior, I have a simple central difference. At the boundaries
    # everything is one sided.
    dZdx = np.zeros(N)
    if N > 1:
        dZdx[1:-1] = (Z[2:] - Z[:-2]) / (2.0 * dx)
        dZdx[0] = (Z[1] - Z[0]) / dx
        dZdx[-1] = (Z[-1] - Z[-2]) / dx
    source_topo = -g * h * dZdx

    # Update variables
    h_new = h - (dt / dx) * (F_mass[1:] - F_mass[:-1]) + dt * S
    hu_new = hu - (dt / dx) * (F_mom[1:] - F_mom[:-1]) + dt * S * u + dt * source_topo

    # Enforce non-negatice depth (dry-cell treatment)
    h_new = np.maximum(h_new, 0.0)
    dry = h_new < h_eps
    hu_new[dry] = 0.0

    return h_new, hu_new

def run(N: int = 200,
        L: float = 10.0,
        T: float = 1.0,
        cfl: float = 0.5,
        rain_rate: float = 0.0,
        xi_max_factor: float = 4.0,
        N_xi: int = 64,
        output_interval: int = 10) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Run an 1D simulation of the SWE + recharge model on a uniform grid.

    Default initial conditions try to simulate a dam-break scenario (left 
    depth 2, right depth 1, u=0). Topography is flat for simplicity (Z=0).

    Time stepping:
        - dt is chosen after each step from:
            dt = cfl * dx / s_max,
          where s_max = max_i( |u_i| + sqrt( 2 g h_i ) )

    Parameters:
        N   :   int
            Number of cells
        L   :   float
            Domain length. Domain is [0, L]
        T   :   float
            Final time
        cfl :   float   
            CFL number in (0, 1]
        rain_rate   :   float
            Uniform rainfall rate used to build S = R - I. If R = I = 0, then 
            there is no recharge and I recover the original SWE dam break.
        xi_max_factor   :   float
            Sets kinetic velocity range xi in [-xi_max, xi_max] where
                xi_max = xi_max_factor * sqrt(2 g max(h_initial)).
        N_xi    :   int
            Number of points in the xi-grid. This is used for the quadrature 
            resolution, the higher the better.
        output_interval :   int
            Print progress to visually see that everything is working

    Returns:
        x   :   np.ndarray
            Cell-centered coordinates
        Z   :   np.ndarray
            Bed elevation at cell centers
        h   :   np.ndarray
            Final depth
        u   :   np.ndarray
            Final velocity
    """
    # Get grid spacing
    dx = L / N

    # Build the grid
    x = (np.arange(N) + 0.5) * dx

    # Initial conditions: try dam break
    h = np.ones(N) * 1.0
    h[x < L / 2.0] = 2.0    # dam is at x = 5, left side has more water
    u = np.zeros(N)
    hu = h * u

    # Flat bed, don't bother for something extreme for now
    Z = np.zeros(N)

    # Rainfall & Infiltration
    R = np.ones(N) * rain_rate      # just use rainfall for now
    I = None                        # skip infiltration for later

    # Kinetic velocity grid
    c0 = np.sqrt(2.0 * g * np.max(h))
    xi_max = xi_max_factor * c0
    xi = np.linspace(-xi_max, xi_max, N_xi)
    dxi = xi[1] - xi[0]

    # Time loop
    t = 0.0
    step = 0
    while t < T:
        # Dry-cell safeguard
        h_pos = np.maximum(h, 1e-8)
        u = hu / h_pos

        # Compute max wave speed, and appropriate time step
        smax = max_wave_speed(h, u)
        dt = cfl * dx / (smax + 1e-12)
        if t + dt > T:
            dt = T - t
        
        # Perform a kinetic step
        h, hu = step_kinetic(h, hu, Z, R, I, dx, dt, xi, dxi)
        
        # Update time and step count
        t += dt
        step += 1
        
        # Print what is going on in CLI
        if step % output_interval == 0:
            print(f"t = {t:.3f}, step = {step}")
    
    # Recover final velocity
    h_pos = np.maximum(h, 1e-8)
    u = hu / h_pos
    return x, Z, h_pos, u

def plotter(x: np.ndarray,
            Z: np.ndarray,
            h: np.ndarray,
            u: np.ndarray,
            rain_rate: float,
            title_prefix: str = "Kinetic SWE + Recharge") -> None:
    """
    Plot relevant variables for visual representation of what is going on.
    """
    eta = h + Z
    q = h * u
    fig, axs = plt.subplots(2, 2, figsize=(10, 6), sharex=True)
    axs = axs.ravel()

    # Bed & Free surface
    axs[0].plot(x, Z, label="bed Z(x)")
    axs[0].plot(x, eta, label="free surface η(x)")
    axs[0].set_ylabel("Elevation")
    axs[0].set_title("Bed & Surface")
    axs[0].legend()

    # Water depth
    axs[1].plot(x, h)
    axs[1].set_ylabel("h(x)")
    axs[1].set_title("Water Depth")

    # Velocity
    axs[2].plot(x, u)
    axs[2].set_xlabel("x")
    axs[2].set_ylabel("u(x)")
    axs[2].set_title("Velocity")

    # Discharge
    axs[3].plot(x, q)
    axs[3].set_xlabel("x")
    axs[3].set_ylabel("q(x) = h*u")
    axs[3].set_title("Discharge")

    fig.suptitle(f"{title_prefix} (rain_rate = {rain_rate})", y = 0.98)
    fig.tight_layout()
    plt.show()

if __name__ == "__main__":
    # Change this into something mediocre to just add rainfall to the scheme
    rain_rate = 0.0

    x, Z, h, u = run(
            N = 200,
            L = 10.0,
            T = 0.5,
            cfl = 0.5,
            rain_rate = rain_rate,
            xi_max_factor = 4.0,
            N_xi = 1024,            # higher the better
            output_interval=20,
            )


    print("Final min/max h:", h.min(), h.max())
    print("Final min/max u:", u.min(), u.max())

    # Plot stuff
    plotter(x, Z, h, u, rain_rate=rain_rate)
